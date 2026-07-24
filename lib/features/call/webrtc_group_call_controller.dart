import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../models/app_user.dart';
import '../../models/group_call.dart';
import '../../repositories/group_call_repository.dart';

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

  GroupCallConnectionState _state = GroupCallConnectionState.connecting;
  GroupCallConnectionState get state => _state;

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

      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        },
        'video': isVideo
            ? {
                'facingMode': 'user',
                'width': {'ideal': 1280},
                'height': {'ideal': 720},
              }
            : false,
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

  @override
  void dispose() {
    _presenceTimer?.cancel();
    _participantsSub?.cancel();
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
