import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../models/app_user.dart';
import '../../models/group_call.dart';
import '../../repositories/group_call_repository.dart';
import 'call_sound_player.dart';
import 'webrtc_media_constraints.dart';

enum GroupCallConnectionState { connecting, active, ended }

/// STUNに加えてTURN（自前coturn）を使う。メッシュ型はペア数が
/// N(N-1)/2に増えるため、1対1よりTURNの必要性が高い
/// （2026-07-24、ユーザー確認の上でTURN自前運用の方針に決定）。
/// coturnサーバー自体の構築（VM・DNS・証明書）は別途インフラ作業として必要で、
/// ここではURL・認証情報を設定するだけの状態。実際のサーバーが立つまでは
/// STUNのみで動作する（未設定時は空文字のままiceServersから除外する）。
const _turnUrl = String.fromEnvironment('DAIDAI_TURN_URL');
const _turnUsername = String.fromEnvironment('DAIDAI_TURN_USERNAME');
const _turnCredential = String.fromEnvironment('DAIDAI_TURN_CREDENTIAL');

Map<String, dynamic> get _rtcConfiguration => {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
        if (_turnUrl.isNotEmpty)
          {
            'urls': _turnUrl,
            'username': _turnUsername,
            'credential': _turnCredential,
          },
      ],
    };

/// 参加者ごとの在室確認ハートビートの送信間隔。
const _presenceHeartbeatInterval = Duration(seconds: 15);

/// これより長くハートビートが途絶えた参加者は離脱扱いにする。
const _presenceStaleAfter = Duration(seconds: 45);

/// 広場（グループ）通話のWebRTCシグナリング・複数`RTCPeerConnection`の
/// ライフサイクルを管理する。メッシュ型P2Pのため、参加者が増減するたびに
/// 自分以外の全参加者との接続を動的に張り直す。通話ごとにインスタンス化し、
/// 画面を離れる際にdispose()すること。
class WebrtcGroupCallController extends ChangeNotifier {
  WebrtcGroupCallController({
    required this.groupCallId,
    required this.currentUser,
    required this.isVideo,
    required GroupCallRepository groupCallRepository,
  }) : _repository = groupCallRepository;

  final String groupCallId;
  final AppUser currentUser;
  final bool isVideo;
  final GroupCallRepository _repository;

  /// ビデオ通話時の自分のカメラプレビュー用。音声のみの通話では使わない。
  final RTCVideoRenderer localRenderer = RTCVideoRenderer();

  /// 相手ごとのリモート映像（音声のみの通話でも、音声再生のために
  /// レンダラー自体は保持する）。UI側はこのMapのキー（=相手のuserId）を
  /// 元にグリッドを組む。
  final Map<String, RTCVideoRenderer> remoteRenderers = {};

  final Map<String, RTCPeerConnection> _peerConnections = {};
  final Map<String, StreamSubscription> _peerLinkSubs = {};
  final Map<String, StreamSubscription> _peerCandidateSubs = {};
  final Map<String, bool> _answerApplied = {};

  MediaStream? _localStream;
  StreamSubscription<List<CallParticipant>>? _participantsSub;
  Timer? _presenceTimer;

  /// 参加者の入退室ブリップ再生。
  final _soundPlayer = CallSoundPlayer();
  Set<String> _previousLiveOtherIds = {};
  bool _hasReceivedFirstSnapshot = false;

  GroupCallConnectionState _state = GroupCallConnectionState.connecting;
  GroupCallConnectionState get state => _state;

  bool _speakerOn = true;
  bool get speakerOn => _speakerOn;

  int _cameraIndex = 0;

  bool _switchingCamera = false;
  bool get switchingCamera => _switchingCamera;

  List<CallParticipant> _participants = [];

  /// 自分以外の参加者（ハートビートが途絶えている＝離脱扱いの相手は除く）。
  List<CallParticipant> get remoteParticipants => _participants
      .where((p) => p.userId != currentUser.userId && !_isStale(p))
      .toList();

  bool _isStale(CallParticipant participant) {
    final lastSeenAt = participant.lastSeenAt;
    if (lastSeenAt == null) return false;
    return DateTime.now().difference(lastSeenAt.toDate()) >
        _presenceStaleAfter;
  }

  bool _muted = false;
  bool get muted => _muted;

  bool _cameraOff = false;
  bool get cameraOff => _cameraOff;

  String? _error;
  String? get error => _error;

  Future<void> initialize() async {
    try {
      if (isVideo) await localRenderer.initialize();

      // 音声制約はプラットフォームごとの既知の問題を踏まえて
      // webrtc_media_constraints.dartに集約している（本格的なRNNoise統合は
      // フェーズ3の別プロジェクト。詳細は会話参照）。
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': buildAudioConstraints(),
        'video': isVideo ? buildVideoConstraints() : false,
      });

      if (isVideo) {
        localRenderer.srcObject = _localStream;
      }

      await _repository.joinGroupCall(
        groupCallId: groupCallId,
        user: currentUser,
      );

      _state = GroupCallConnectionState.active;
      notifyListeners();
      unawaited(_applySpeakerphoneWithRetry());

      _presenceTimer = Timer.periodic(_presenceHeartbeatInterval, (_) {
        _repository.touchPresence(
          groupCallId: groupCallId,
          userId: currentUser.userId,
        );
        // ハートビート失効による離脱反映は新しいFirestoreスナップショットが
        // 来ないと再評価されないため、定期的にUIへ再描画を促す。
        notifyListeners();
      });

      _participantsSub =
          _repository.watchParticipants(groupCallId).listen(_onParticipants);
    } catch (e) {
      _error = '通話を開始できませんでした（マイク・カメラの利用を許可してください）: $e';
      _state = GroupCallConnectionState.ended;
      notifyListeners();
    }
  }

  void _onParticipants(List<CallParticipant> participants) {
    _participants = participants;

    final liveOtherIds = participants
        .where((p) => p.userId != currentUser.userId && !_isStale(p))
        .map((p) => p.userId)
        .toSet();

    // 参加者リストそのものの出現/消失を検知して入退室音を鳴らす
    // （_peerConnections.keysとの差分だと接続確立タイミングに引きずられるため、
    // 別途スナップショットを保持する）。初回スナップショットは既に居た人を
    // 「新規参加」と誤検知しないよう無音でシードする（Discordと同じ挙動）。
    if (!_hasReceivedFirstSnapshot) {
      _hasReceivedFirstSnapshot = true;
      _previousLiveOtherIds = liveOtherIds;
    } else {
      if (liveOtherIds.difference(_previousLiveOtherIds).isNotEmpty) {
        _soundPlayer.playJoinBlip();
      }
      if (_previousLiveOtherIds.difference(liveOtherIds).isNotEmpty) {
        _soundPlayer.playLeaveBlip();
      }
      _previousLiveOtherIds = liveOtherIds;
    }

    for (final userId in liveOtherIds) {
      if (!_peerConnections.containsKey(userId)) {
        _connectToPeer(userId);
      }
    }
    for (final userId in [..._peerConnections.keys]) {
      if (!liveOtherIds.contains(userId)) {
        _disconnectFromPeer(userId);
      }
    }

    notifyListeners();
  }

  Future<void> _connectToPeer(String otherUserId) async {
    final isUserA = currentUser.userId.compareTo(otherUserId) < 0;
    final pairId = CallPeerLink.idFor(currentUser.userId, otherUserId);

    final renderer = RTCVideoRenderer();
    await renderer.initialize();
    remoteRenderers[otherUserId] = renderer;

    final peerConnection = await createPeerConnection(_rtcConfiguration);
    _peerConnections[otherUserId] = peerConnection;

    for (final track in _localStream!.getTracks()) {
      await peerConnection.addTrack(track, _localStream!);
    }

    peerConnection.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        renderer.srcObject = event.streams.first;
      }
    };

    peerConnection.onIceCandidate = (candidate) {
      if (candidate.candidate == null) return;
      _repository.addPeerCandidate(
        groupCallId: groupCallId,
        pairId: pairId,
        isUserA: isUserA,
        candidate: {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        },
      );
    };

    _peerCandidateSubs[otherUserId] = _repository
        .watchPeerCandidates(
          groupCallId: groupCallId,
          pairId: pairId,
          isUserA: isUserA,
        )
        .listen((candidates) {
      for (final data in candidates) {
        peerConnection.addCandidate(
          RTCIceCandidate(
            data['candidate'] as String,
            data['sdpMid'] as String?,
            data['sdpMLineIndex'] as int?,
          ),
        );
      }
    });

    await _repository.initiatePeerLink(
      groupCallId: groupCallId,
      userAId: currentUser.userId,
      userBId: otherUserId,
    );

    _answerApplied[pairId] = false;
    _peerLinkSubs[otherUserId] = _repository
        .watchPeerLink(groupCallId: groupCallId, pairId: pairId)
        .listen((link) async {
      if (link == null) return;
      if (isUserA) {
        if (link.answer != null && _answerApplied[pairId] != true) {
          _answerApplied[pairId] = true;
          await peerConnection.setRemoteDescription(
            RTCSessionDescription(
              link.answer!['sdp'] as String,
              link.answer!['type'] as String,
            ),
          );
        }
      } else {
        if (link.offer != null && _answerApplied[pairId] != true) {
          _answerApplied[pairId] = true;
          await peerConnection.setRemoteDescription(
            RTCSessionDescription(
              link.offer!['sdp'] as String,
              link.offer!['type'] as String,
            ),
          );
          final answer = await peerConnection.createAnswer();
          await peerConnection.setLocalDescription(answer);
          await _repository.setPeerAnswer(
            groupCallId: groupCallId,
            pairId: pairId,
            answer: {'sdp': answer.sdp, 'type': answer.type},
          );
        }
      }
    });

    if (isUserA) {
      final offer = await peerConnection.createOffer();
      await peerConnection.setLocalDescription(offer);
      await _repository.setPeerOffer(
        groupCallId: groupCallId,
        pairId: pairId,
        offer: {'sdp': offer.sdp, 'type': offer.type},
      );
    }
  }

  void _disconnectFromPeer(String otherUserId) {
    _peerLinkSubs.remove(otherUserId)?.cancel();
    _peerCandidateSubs.remove(otherUserId)?.cancel();
    _peerConnections.remove(otherUserId)?.close();
    remoteRenderers.remove(otherUserId)?.dispose();
  }

  Future<void> leave() async {
    if (_state == GroupCallConnectionState.ended) return;
    await _repository.leaveGroupCall(
      groupCallId: groupCallId,
      userId: currentUser.userId,
    );
    _state = GroupCallConnectionState.ended;
    notifyListeners();
  }

  void toggleMute() {
    _muted = !_muted;
    for (final track in _localStream?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      track.enabled = !_muted;
    }
    _repository.updateParticipantState(
      groupCallId: groupCallId,
      userId: currentUser.userId,
      micMuted: _muted,
    );
    notifyListeners();
  }

  void toggleCamera() {
    _cameraOff = !_cameraOff;
    for (final track in _localStream?.getVideoTracks() ?? <MediaStreamTrack>[]) {
      track.enabled = !_cameraOff;
    }
    _repository.updateParticipantState(
      groupCallId: groupCallId,
      userId: currentUser.userId,
      cameraOff: _cameraOff,
    );
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
    if (_state == GroupCallConnectionState.active) {
      await _applySpeakerphone(_speakerOn);
    }
  }

  void toggleSpeaker() {
    _speakerOn = !_speakerOn;
    _applySpeakerphone(_speakerOn);
    notifyListeners();
  }

  Future<void> switchCamera() async {
    // 連打による多重実行を防ぐ（実機で「重くなる」報告の一因だった）。
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
      // 取り除き、新しいトラックを同じ_localStreamに追加する副作用を持つが、
      // それだけではRTCVideoRenderer（Web実装、代入時点でトラックを
      // スナップショットする）が古い（停止済みの）トラックを表示し続け
      // 「切替後に画面が真っ黒になる」不具合になる。加えて、各相手との
      // RTCPeerConnectionのRTCRtpSenderにも明示的にreplaceTrackしないと
      // 新しい映像が送信されない（グループ通話は相手の人数分Peer
      // Connectionがあるため、全員分に反映する必要がある）。
      final newTrack = _localStream?.getVideoTracks().firstOrNull;
      if (newTrack != null) {
        localRenderer.srcObject = _localStream;
        for (final pc in _peerConnections.values) {
          final sender = (await pc.getSenders())
              .where((s) => s.track?.kind == 'video')
              .firstOrNull;
          await sender?.replaceTrack(newTrack);
        }
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
    _presenceTimer?.cancel();
    _participantsSub?.cancel();
    _soundPlayer.dispose();
    for (final userId in [..._peerConnections.keys]) {
      _disconnectFromPeer(userId);
    }
    for (final track in _localStream?.getTracks() ?? <MediaStreamTrack>[]) {
      track.stop();
    }
    _localStream?.dispose();
    localRenderer.dispose();
    super.dispose();
  }
}
