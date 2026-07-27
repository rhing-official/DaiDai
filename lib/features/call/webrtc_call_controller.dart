import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../models/call.dart';
import '../../repositories/call_repository.dart';
import 'call_sound_player.dart';
import 'rtc_config.dart';
import 'webrtc_media_constraints.dart';

enum CallConnectionState { connecting, active, ended }

/// 1件の音声通話のWebRTCシグナリング・PeerConnectionのライフサイクルを管理する。
/// 通話ごとにインスタンス化し、画面を離れる際にdispose()すること。
class WebrtcCallController extends ChangeNotifier {
  WebrtcCallController({
    required this.call,
    required this.isCaller,
    required CallRepository callRepository,
  }) : _callRepository = callRepository;

  final Call call;
  final bool isCaller;
  final CallRepository _callRepository;

  final RTCVideoRenderer remoteRenderer = RTCVideoRenderer();

  /// ビデオ通話時の自分のカメラプレビュー用。音声のみの通話では使わない。
  final RTCVideoRenderer localRenderer = RTCVideoRenderer();

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  StreamSubscription<Call?>? _callSub;
  StreamSubscription<List<Map<String, dynamic>>>? _candidatesSub;
  bool _answerApplied = false;

  // setRemoteDescriptionが完了するより先にICE candidateが届くと、
  // addCandidateが例外を投げて無言で失われてしまう競合状態があったため、
  // 完了するまで候補をバッファし、完了後にまとめて適用する。
  // watchCandidatesは毎回累積リスト全体を再送してくるため、適用済みの
  // 候補をキーで重複排除する。
  bool _remoteDescriptionSet = false;
  final List<Map<String, dynamic>> _pendingRemoteCandidates = [];
  final Set<String> _appliedCandidateKeys = {};

  bool _connectionIssue = false;
  bool get connectionIssue => _connectionIssue;

  /// 通話の効果音（着信音）再生。画面側が着信中にループ再生を開始/停止する。
  final soundPlayer = CallSoundPlayer();

  CallConnectionState _state = CallConnectionState.connecting;
  CallConnectionState get state => _state;

  bool _muted = false;
  bool get muted => _muted;

  bool _cameraOff = false;
  bool get cameraOff => _cameraOff;

  bool _accepting = false;
  bool get accepting => _accepting;

  bool _speakerOn = true;
  bool get speakerOn => _speakerOn;

  int _cameraIndex = 0;

  bool _switchingCamera = false;
  bool get switchingCamera => _switchingCamera;

  String? _error;
  String? get error => _error;

  Future<void> initialize() async {
    try {
      await remoteRenderer.initialize();
      if (call.isVideo) await localRenderer.initialize();

      // 音声制約はプラットフォームごとの既知の問題を踏まえて
      // webrtc_media_constraints.dartに集約している（本格的なRNNoise統合は
      // フェーズ3の別プロジェクト。詳細は会話参照）。
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': buildAudioConstraints(),
        'video': call.isVideo ? buildVideoConstraints() : false,
      });

      if (call.isVideo) {
        localRenderer.srcObject = _localStream;
      }

      _peerConnection = await createPeerConnection(buildRtcConfiguration());
      for (final track in _localStream!.getTracks()) {
        await _peerConnection!.addTrack(track, _localStream!);
      }

      _peerConnection!.onTrack = (event) {
        if (event.streams.isNotEmpty) {
          remoteRenderer.srcObject = event.streams.first;
        }
      };

      _peerConnection!.onIceConnectionState = (iceState) {
        final issue = iceState == RTCIceConnectionState.RTCIceConnectionStateFailed ||
            iceState == RTCIceConnectionState.RTCIceConnectionStateDisconnected;
        if (issue != _connectionIssue) {
          _connectionIssue = issue;
          notifyListeners();
        }
      };

      _peerConnection!.onIceCandidate = (candidate) {
        if (candidate.candidate == null) return;
        _callRepository.addCandidate(
          callId: call.callId,
          isCaller: isCaller,
          candidate: {
            'candidate': candidate.candidate,
            'sdpMid': candidate.sdpMid,
            'sdpMLineIndex': candidate.sdpMLineIndex,
          },
        );
      };

      _candidatesSub = _callRepository
          .watchCandidates(callId: call.callId, isCaller: isCaller)
          .listen((candidates) {
        for (final data in candidates) {
          _applyOrBufferCandidate(data);
        }
      });

      if (isCaller) {
        await _startAsCaller();
      } else {
        // 着信側はユーザーが応答ボタンを押すまでSDP応答を送らない
        // （accept()参照）。ここでは発信者側キャンセルの監視のみ行う。
        _watchForCancelWhileRinging();
      }
    } catch (e) {
      _error = '通話を開始できませんでした（マイクの利用を許可してください）: $e';
      _state = CallConnectionState.ended;
      notifyListeners();
    }
  }

  /// setRemoteDescription完了前に届いた候補はバッファに貯め、完了後に
  /// まとめて適用する。watchCandidatesは毎回累積リスト全体を再送してくる
  /// ため、候補ごとのキーで重複適用を防ぐ。
  void _applyOrBufferCandidate(Map<String, dynamic> data) {
    final key = '${data['candidate']}|${data['sdpMid']}|${data['sdpMLineIndex']}';
    if (_appliedCandidateKeys.contains(key)) return;
    if (!_remoteDescriptionSet) {
      _pendingRemoteCandidates.add(data);
      return;
    }
    _appliedCandidateKeys.add(key);
    _peerConnection
        ?.addCandidate(
          RTCIceCandidate(
            data['candidate'] as String,
            data['sdpMid'] as String?,
            data['sdpMLineIndex'] as int?,
          ),
        )
        .catchError((_) {
      // 相手のPeerConnectionが既に閉じている等。通話自体は継続させる。
    });
  }

  void _flushPendingCandidates() {
    _remoteDescriptionSet = true;
    final pending = [..._pendingRemoteCandidates];
    _pendingRemoteCandidates.clear();
    for (final data in pending) {
      _applyOrBufferCandidate(data);
    }
  }

  Future<void> _startAsCaller() async {
    final offer = await _peerConnection!.createOffer();
    await _peerConnection!.setLocalDescription(offer);
    await _callRepository.setOffer(call.callId, {
      'sdp': offer.sdp,
      'type': offer.type,
    });

    _callSub = _callRepository.watchCall(call.callId).listen((updated) async {
      if (updated == null || _isTerminal(updated.status)) {
        _finish();
        return;
      }
      if (updated.answer != null && !_answerApplied) {
        _answerApplied = true;
        await _peerConnection?.setRemoteDescription(
          RTCSessionDescription(
            updated.answer!['sdp'] as String,
            updated.answer!['type'] as String,
          ),
        );
        _flushPendingCandidates();
        _state = CallConnectionState.active;
        notifyListeners();
        unawaited(_applySpeakerphoneWithRetry());
      }
    });
  }

  /// 応答前（着信中）に発信者が通話をキャンセル・終了した場合に
  /// 着信画面を閉じるための軽量な監視。accept()呼び出しでキャンセルする。
  void _watchForCancelWhileRinging() {
    _callSub = _callRepository.watchCall(call.callId).listen((updated) {
      if (updated == null || _isTerminal(updated.status)) {
        _finish();
      }
    });
  }

  /// ユーザーが応答ボタンを押した時だけSDP応答を生成・送信する。
  /// （それまでは_startAsCallee()を呼ばないことで、着信＝自動応答という
  /// 挙動を避ける。）
  Future<void> accept() async {
    if (_accepting || _state != CallConnectionState.connecting) return;
    _accepting = true;
    notifyListeners();
    await _callSub?.cancel();
    await _startAsCallee();
  }

  Future<void> _startAsCallee() async {
    var offer = call.offer;
    offer ??= await _callRepository
        .watchCall(call.callId)
        .firstWhere((c) => c?.offer != null)
        .then((c) => c!.offer);

    await _peerConnection!.setRemoteDescription(
      RTCSessionDescription(offer!['sdp'] as String, offer['type'] as String),
    );
    _flushPendingCandidates();
    final answer = await _peerConnection!.createAnswer();
    await _peerConnection!.setLocalDescription(answer);
    await _callRepository.setAnswer(call.callId, {
      'sdp': answer.sdp,
      'type': answer.type,
    });

    _state = CallConnectionState.active;
    notifyListeners();
    unawaited(_applySpeakerphoneWithRetry());

    _callSub = _callRepository.watchCall(call.callId).listen((updated) {
      if (updated == null || _isTerminal(updated.status)) {
        _finish();
      }
    });
  }

  bool _isTerminal(CallStatus status) {
    return status == CallStatus.ended ||
        status == CallStatus.declined ||
        status == CallStatus.missed;
  }

  void _finish() {
    if (_state == CallConnectionState.ended) return;
    _state = CallConnectionState.ended;
    notifyListeners();
  }

  Future<void> decline() async {
    await _callRepository.updateStatus(call.callId, CallStatus.declined);
    _finish();
  }

  Future<void> hangUp() async {
    await _callRepository.updateStatus(call.callId, CallStatus.ended);
    _finish();
  }

  void toggleMute() {
    _muted = !_muted;
    for (final track in _localStream?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      track.enabled = !_muted;
    }
    notifyListeners();
  }

  void toggleCamera() {
    _cameraOff = !_cameraOff;
    for (final track in _localStream?.getVideoTracks() ?? <MediaStreamTrack>[]) {
      track.enabled = !_cameraOff;
    }
    notifyListeners();
  }

  Future<void> _applySpeakerphone(bool enable) async {
    if (kIsWeb) return; // Webはブラウザの既定オーディオ出力に依存し対象外。
    try {
      await Helper.setSpeakerphoneOn(enable);
    } catch (_) {
      // 一部プラットフォームで未対応/失敗する既知の問題（iOS: flutter-webrtc
      // issue #1290, #1098, #1032, #1427）。失敗しても通話自体は継続させる。
    }
  }

  /// iOSでは接続直後にsetSpeakerphoneOnを呼んでも、数秒後に音声ルートが
  /// 勝手に戻ることがある既知の競合状態があるため、接続完了直後に一度適用し、
  /// 少し間を空けてもう一度適用する。
  Future<void> _applySpeakerphoneWithRetry() async {
    await _applySpeakerphone(_speakerOn);
    await Future.delayed(const Duration(seconds: 2));
    if (_state == CallConnectionState.active) {
      await _applySpeakerphone(_speakerOn);
    }
  }

  void toggleSpeaker() {
    _speakerOn = !_speakerOn;
    _applySpeakerphone(_speakerOn);
    notifyListeners();
  }

  Future<void> switchCamera() async {
    // 連打による多重実行を防ぐ（実機で「重くなる」報告の一因だった。
    // 前のgetUserMedia/switchCameraが終わらないうちに次を呼ぶと処理が
    // 積み重なる）。
    if (_switchingCamera) return;
    final videoTracks = _localStream?.getVideoTracks() ?? <MediaStreamTrack>[];
    if (videoTracks.isEmpty) return;
    _switchingCamera = true;
    notifyListeners();
    try {
      final track = videoTracks.first;
      if (kIsWeb) {
        final cameras = await Helper.cameras;
        if (cameras.length < 2) return;
        _cameraIndex = (_cameraIndex + 1) % cameras.length;
        await Helper.switchCamera(track, cameras[_cameraIndex].deviceId, _localStream);
      } else {
        await Helper.switchCamera(track);
      }
      // Web版のHelper.switchCameraは古いトラックをstop()して_localStreamから
      // 取り除き、新しいトラックを同じ_localStreamに追加するという副作用を
      // 持つが、それだけでは以下の2つが反映されず「切替後に画面が真っ黒に
      // なる」「相手にも古い映像が送られ続ける」不具合になっていた:
      // 1. RTCVideoRenderer（Web実装）は代入された時点のトラックを
      //    スナップショットとして保持するため、再代入しないと古い
      //    （停止済みの）トラックを表示し続ける。
      // 2. RTCPeerConnectionのRTCRtpSenderは明示的にreplaceTrackしない限り
      //    新しいトラックを送信しない。
      // ネイティブ版はHelper.switchCameraがトラックの実体を差し替えず
      // カメラキャプチャセッションだけを切り替えるため本来不要だが、
      // 同じコードで両対応させても無害（同一トラックへの再代入・
      // replaceTrackは実質no-op）。
      final newTrack = _localStream?.getVideoTracks().firstOrNull;
      if (newTrack != null) {
        localRenderer.srcObject = _localStream;
        final sender = (await _peerConnection?.getSenders() ?? [])
            .where((s) => s.track?.kind == 'video')
            .firstOrNull;
        await sender?.replaceTrack(newTrack);
      }
    } catch (_) {
      // 切替可能なカメラが1つしかない環境など。現状維持。
    } finally {
      _switchingCamera = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _callSub?.cancel();
    _candidatesSub?.cancel();
    soundPlayer.dispose();
    for (final track in _localStream?.getTracks() ?? <MediaStreamTrack>[]) {
      track.stop();
    }
    _localStream?.dispose();
    _peerConnection?.close();
    localRenderer.dispose();
    remoteRenderer.dispose();
    super.dispose();
  }
}
