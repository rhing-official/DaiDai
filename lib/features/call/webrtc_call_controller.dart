import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../models/call.dart';
import '../../repositories/call_repository.dart';
import '../../repositories/direct_message_repository.dart';
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
    required DirectMessageRepository directMessageRepository,
  }) : _callRepository = callRepository,
       _directMessageRepository = directMessageRepository;

  final Call call;
  final bool isCaller;
  final CallRepository _callRepository;
  final DirectMessageRepository _directMessageRepository;

  final RTCVideoRenderer remoteRenderer = RTCVideoRenderer();

  /// ビデオ通話時の自分のカメラプレビュー用。音声のみの通話では使わない。
  final RTCVideoRenderer localRenderer = RTCVideoRenderer();

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  StreamSubscription<Call?>? _callSub;
  StreamSubscription<List<Map<String, dynamic>>>? _candidatesSub;

  // offer/answerは通話開始時の1回きりではなく、通話中の音声⇔ビデオ切替
  // （setVideoEnabled参照）のたびに同じフィールドへ上書きされる。
  // 「新着かどうか」は一意な採番ではなくSDP文字列そのものの差分で判定し、
  // 自分が直前に書き込んだ値（_pendingLocalXxx）と既に適用済みの値
  // （_lastAppliedXxx）のどちらとも一致しない場合だけ「相手からの新着」
  // として扱う。これにより発信/着信・初回接続/再ネゴシエーションを
  // 問わず同じロジックで扱える。
  String? _pendingLocalOfferSdp;
  String? _pendingLocalAnswerSdp;
  String? _lastAppliedOfferSdp;
  String? _lastAppliedAnswerSdp;

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

  /// 自分が現在ビデオ通話として動作しているか（[call.isVideo]は開始時点の
  /// 値のままなので、通話中の切替を反映する可変の状態として別に持つ）。
  /// 音声⇔ビデオの切替は自分側にのみ適用され、相手には影響しない。
  late bool _isVideo = call.isVideo;
  bool get isVideo => _isVideo;

  /// 相手が現在ビデオ通話として動作しているか。自分の映像トラックの
  /// 有無には影響せず、UI側が相手の映像表示/プレースホルダーの
  /// 切替に使うだけの表示用フラグ。
  late bool _remoteIsVideo = isCaller ? call.calleeIsVideo : call.callerIsVideo;
  bool get remoteIsVideo => _remoteIsVideo;

  bool _localRendererInitialized = false;

  /// 通話が接続状態（active）になった時刻。発信者側のみ、通話終了時に
  /// この時刻から通話履歴メッセージの通話時間を計算するために使う。
  DateTime? _connectedAt;

  bool _switchingCallType = false;
  bool get switchingCallType => _switchingCallType;

  bool _accepting = false;
  bool get accepting => _accepting;

  bool _speakerOn = true;
  bool get speakerOn => _speakerOn;

  int _cameraIndex = 0;

  bool _switchingCamera = false;
  bool get switchingCamera => _switchingCamera;

  /// 前後（イン/アウト）カメラ切替ボタンの表示可否に使う、映像入力
  /// デバイスの台数（2026-08-19追加）。`getUserMedia`成功後（＝端末の
  /// カメラ利用許可が下りた後）にだけ正確に取得できるため、映像取得の
  /// 直後（[initialize]・[_enableLocalVideoTrack]）に1回だけ取得し直す
  /// （継続的な監視は行わない）。
  int? _localCameraCount;
  bool get hasMultipleCameras => (_localCameraCount ?? 0) >= 2;

  Future<void> _refreshCameraCount() async {
    try {
      _localCameraCount = (await Helper.cameras).length;
      notifyListeners();
    } catch (_) {
      // 取得に失敗しても前後切替ボタンを出さないだけで通話自体は継続する。
    }
  }

  String? _error;
  String? get error => _error;

  Future<void> initialize() async {
    try {
      await remoteRenderer.initialize();
      if (call.isVideo) {
        await localRenderer.initialize();
        _localRendererInitialized = true;
      }

      // 音声制約はプラットフォームごとの既知の問題を踏まえて
      // webrtc_media_constraints.dartに集約している（本格的なRNNoise統合は
      // フェーズ3の別プロジェクト。詳細は会話参照）。
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': buildAudioConstraints(),
        'video': call.isVideo ? buildVideoConstraints() : false,
      });

      if (call.isVideo) {
        localRenderer.srcObject = _localStream;
        unawaited(_refreshCameraCount());
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
        final issue =
            iceState == RTCIceConnectionState.RTCIceConnectionStateFailed ||
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
    final key =
        '${data['candidate']}|${data['sdpMid']}|${data['sdpMLineIndex']}';
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
    _pendingLocalOfferSdp = offer.sdp;
    await _callRepository.setOffer(call.callId, {
      'sdp': offer.sdp,
      'type': offer.type,
    });
    _startPerpetualWatcher();
  }

  /// 初回のオファー/アンサー交換が終わった後も含めて、通話が終わるまで
  /// 継続してcallドキュメントを監視する。offer/answerフィールドは
  /// 通話開始時の1回だけでなく、通話中の音声⇔ビデオ切替（setVideoEnabled）
  /// のたびに上書きされるため、「自分が直前に送った値」でも「既に適用済みの
  /// 値」でもない新しい値が来たら、相手からの新規オファー/アンサーとして
  /// 都度適用する。発信者・着信者どちらの役割でも同じロジックで扱える。
  void _startPerpetualWatcher() {
    _callSub?.cancel();
    _callSub = _callRepository.watchCall(call.callId).listen((updated) async {
      if (updated == null || _isTerminal(updated.status)) {
        _finish();
        return;
      }

      // 相手が音声⇔ビデオを切り替えた場合も、こちら側の映像トラックは
      // 一切変更しない（切替は本人側にのみ適用される）。UI表示用に相手の
      // 状態だけ反映する。実際の映像の出し分けは、この直後に届く相手からの
      // オファー（映像m-lineの追加/削除）に対してアンサーするだけで済む
      // （自分の映像トラックが無ければ自動的にrecvonlyのアンサーになる）。
      final remoteVideo = isCaller
          ? updated.calleeIsVideo
          : updated.callerIsVideo;
      if (remoteVideo != _remoteIsVideo) {
        _remoteIsVideo = remoteVideo;
        notifyListeners();
      }

      final offerSdp = updated.offer?['sdp'] as String?;
      if (offerSdp != null &&
          offerSdp != _pendingLocalOfferSdp &&
          offerSdp != _lastAppliedOfferSdp) {
        _lastAppliedOfferSdp = offerSdp;
        await _applyRemoteOfferAndAnswer(updated.offer!);
      }

      final answerSdp = updated.answer?['sdp'] as String?;
      if (answerSdp != null &&
          answerSdp != _pendingLocalAnswerSdp &&
          answerSdp != _lastAppliedAnswerSdp) {
        _lastAppliedAnswerSdp = answerSdp;
        await _peerConnection?.setRemoteDescription(
          RTCSessionDescription(answerSdp, updated.answer!['type'] as String),
        );
        _flushPendingCandidates();
        if (_state != CallConnectionState.active) {
          _state = CallConnectionState.active;
          _connectedAt ??= DateTime.now();
          unawaited(_applySpeakerphoneWithRetry());
        }
        _switchingCallType = false;
        notifyListeners();
      }
    });
  }

  /// 相手から届いたオファー（初回接続時、または相手が音声⇔ビデオを
  /// 切り替えた際の再ネゴシエーション）に対して、アンサーを作って返す。
  Future<void> _applyRemoteOfferAndAnswer(Map<String, dynamic> offerMap) async {
    await _peerConnection!.setRemoteDescription(
      RTCSessionDescription(
        offerMap['sdp'] as String,
        offerMap['type'] as String,
      ),
    );
    _flushPendingCandidates();
    final answer = await _peerConnection!.createAnswer();
    await _peerConnection!.setLocalDescription(answer);
    _pendingLocalAnswerSdp = answer.sdp;
    await _callRepository.setAnswer(call.callId, {
      'sdp': answer.sdp,
      'type': answer.type,
    });
    if (_state != CallConnectionState.active) {
      _state = CallConnectionState.active;
      _connectedAt ??= DateTime.now();
      unawaited(_applySpeakerphoneWithRetry());
    }
    _switchingCallType = false;
    notifyListeners();
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

    // 以後_startPerpetualWatcher()がこの初回オファーを重複適用しないよう、
    // 適用前にキーを記録しておく。
    _lastAppliedOfferSdp = offer!['sdp'] as String;
    await _applyRemoteOfferAndAnswer(offer);
    _startPerpetualWatcher();
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
    // 通話履歴メッセージは発信者側からのみ送る（両側から送ると二重投稿に
    // なるため）。実際に接続（応答）された通話のみが対象で、不在着信・
    // 拒否（_connectedAtが立たないまま終了）の場合は送らない。
    if (isCaller && _connectedAt != null) {
      unawaited(_logCallSummary(_connectedAt!));
    }
  }

  Future<void> _logCallSummary(DateTime startedAt) async {
    final durationSeconds = DateTime.now().difference(startedAt).inSeconds;
    if (durationSeconds <= 0) return;
    try {
      await _directMessageRepository.sendCallSummaryMessage(
        dmId: call.dmId,
        senderId: call.callerId,
        senderRhingId: call.callerRhingId,
        startedAt: startedAt,
        durationSeconds: durationSeconds,
        isVideo: call.isVideo,
      );
    } catch (_) {
      // 通信不安定等。通話自体は既に終了しているため、履歴メッセージの
      // 送信失敗は握りつぶす（再試行の仕組みは持たない）。
    }
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
    for (final track
        in _localStream?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      track.enabled = !_muted;
    }
    notifyListeners();
  }

  /// 通話中に音声通話⇔ビデオ通話を切り替える（映像トラック自体を追加/
  /// 削除して通話の種別そのものを変える）。音声のみで開始した通話には映像用の
  /// track/transceiverが最初から存在しないため、[RTCPeerConnection.addTrack]/
  /// [removeTrack]による再ネゴシエーション（新しいオファー/アンサー交換）が
  /// 必須になる。
  ///
  /// 切り替えは自分側にのみ適用され、相手の映像トラックには一切触れない。
  /// 相手には新しいオファー（映像m-lineの追加/削除）が届くだけで、相手側は
  /// 自分の映像トラックを持っていなければ自動的にrecvonlyでアンサーする
  /// （＝相手のカメラが強制でオン/オフされることはない）。
  Future<void> setVideoEnabled(bool enabled) async {
    if (enabled == _isVideo ||
        _switchingCallType ||
        _state != CallConnectionState.active) {
      return;
    }
    _switchingCallType = true;
    notifyListeners();
    try {
      await _reconcileLocalVideoTo(enabled);
      notifyListeners();
      await _callRepository.updateIsVideo(
        call.callId,
        isCaller: isCaller,
        isVideo: enabled,
      );
      final offer = await _peerConnection!.createOffer();
      await _peerConnection!.setLocalDescription(offer);
      _pendingLocalOfferSdp = offer.sdp;
      await _callRepository.setOffer(call.callId, {
        'sdp': offer.sdp,
        'type': offer.type,
      });
    } catch (_) {
      // ネットワーク瞬断等。ボタンを再度有効にし、ユーザーに再試行させる。
      _switchingCallType = false;
      notifyListeners();
    }
  }

  /// 自分の映像トラックの有無を[targetIsVideo]に合わせる。[setVideoEnabled]
  /// からのみ呼ばれる（自分の操作でのみ自分の映像トラックが変化する）。
  Future<void> _reconcileLocalVideoTo(bool targetIsVideo) async {
    if (targetIsVideo == _isVideo) return;
    if (targetIsVideo) {
      await _enableLocalVideoTrack();
    } else {
      await _disableLocalVideoTrack();
    }
    _isVideo = targetIsVideo;
  }

  Future<void> _enableLocalVideoTrack() async {
    final videoStream = await navigator.mediaDevices.getUserMedia({
      'audio': false,
      'video': buildVideoConstraints(),
    });
    final videoTrack = videoStream.getVideoTracks().first;
    _localStream?.addTrack(videoTrack);
    if (!_localRendererInitialized) {
      await localRenderer.initialize();
      _localRendererInitialized = true;
    }
    localRenderer.srcObject = _localStream;
    await _peerConnection?.addTrack(videoTrack, _localStream!);
    unawaited(_refreshCameraCount());
  }

  Future<void> _disableLocalVideoTrack() async {
    final videoTracks = [...?_localStream?.getVideoTracks()];
    final senders = await _peerConnection?.getSenders() ?? [];
    for (final track in videoTracks) {
      final sender = senders.firstWhereOrNull((s) => s.track?.id == track.id);
      if (sender != null) {
        await _peerConnection?.removeTrack(sender);
      }
      _localStream?.removeTrack(track);
      await track.stop();
    }
    localRenderer.srcObject = null;
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
        await Helper.switchCamera(
          track,
          cameras[_cameraIndex].deviceId,
          _localStream,
        );
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
