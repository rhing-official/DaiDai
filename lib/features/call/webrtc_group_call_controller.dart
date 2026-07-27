import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../models/app_user.dart';
import '../../models/group_call.dart';
import '../../repositories/group_call_repository.dart';
import 'call_sound_player.dart';
import 'rtc_config.dart';
import 'webrtc_media_constraints.dart';

enum GroupCallConnectionState { connecting, active, ended }

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
    required bool isVideo,
    required GroupCallRepository groupCallRepository,
  })  : _isVideo = isVideo,
        _repository = groupCallRepository;

  final String groupCallId;
  final AppUser currentUser;
  final GroupCallRepository _repository;

  /// 現在ビデオ通話として動作しているか（通話中の音声⇔ビデオ切替を
  /// 反映する可変の状態。コンストラクタの`isVideo`は開始時点の初期値）。
  bool _isVideo;
  bool get isVideo => _isVideo;
  bool _localRendererInitialized = false;

  bool _switchingCallType = false;
  bool get switchingCallType => _switchingCallType;

  /// ビデオ通話時の自分のカメラプレビュー用。音声のみの通話では使わない。
  final RTCVideoRenderer localRenderer = RTCVideoRenderer();

  /// 相手ごとのリモート映像（音声のみの通話でも、音声再生のために
  /// レンダラー自体は保持する）。UI側はこのMapのキー（=相手のuserId）を
  /// 元にグリッドを組む。
  final Map<String, RTCVideoRenderer> remoteRenderers = {};

  final Map<String, RTCPeerConnection> _peerConnections = {};
  final Map<String, StreamSubscription> _peerLinkSubs = {};
  final Map<String, StreamSubscription> _peerCandidateSubs = {};

  // peerLink（相手1人ぶんのペア）のoffer/answerフィールドは初回接続時の
  // 1回きりではなく、通話中の音声⇔ビデオ切替のたびに上書きされる。
  // 「新着かどうか」は一意な採番ではなくSDP文字列そのものの差分で判定し、
  // 自分が直前に送った値でも既に適用済みの値でもない場合だけ相手からの
  // 新規オファー/アンサーとして扱う（1対1のWebrtcCallControllerと同じ設計）。
  final Map<String, String?> _pendingLocalOfferSdp = {};
  final Map<String, String?> _pendingLocalAnswerSdp = {};
  final Map<String, String?> _lastAppliedOfferSdp = {};
  final Map<String, String?> _lastAppliedAnswerSdp = {};

  // setRemoteDescriptionが完了するより先にICE candidateが届くと、
  // addCandidateが例外を投げて無言で失われてしまう競合状態があったため、
  // 相手ごとに完了するまで候補をバッファし、完了後にまとめて適用する。
  // watchPeerCandidatesは毎回累積リスト全体を再送してくるため、適用済みの
  // 候補をキーで重複排除する。
  final Map<String, bool> _remoteDescriptionSet = {};
  final Map<String, List<Map<String, dynamic>>> _pendingRemoteCandidates = {};
  final Map<String, Set<String>> _appliedCandidateKeys = {};

  /// 相手ごとのICE接続状態に問題があるか（failed/disconnected）。
  /// UI側はこれを見て、シグナリングは完了しているのに実際には映像/音声が
  /// 流れていない参加者のタイルに控えめな表示を重ねる。
  final Map<String, bool> peerConnectionIssues = {};

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
      if (_isVideo) {
        await localRenderer.initialize();
        _localRendererInitialized = true;
      }

      // 音声制約はプラットフォームごとの既知の問題を踏まえて
      // webrtc_media_constraints.dartに集約している（本格的なRNNoise統合は
      // フェーズ3の別プロジェクト。詳細は会話参照）。
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': buildAudioConstraints(),
        'video': _isVideo ? buildVideoConstraints() : false,
      });

      if (_isVideo) {
        localRenderer.srcObject = _localStream;
      }

      await _repository.joinGroupCall(
        groupCallId: groupCallId,
        user: currentUser,
        isVideo: _isVideo,
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

      // 自分以外の参加者の音声⇔ビデオ状態はCallParticipant.isVideo
      // （このStream経由で届く）を見るだけで、こちらの映像トラックには
      // 一切触れない（切替は本人側にのみ適用される。setVideoEnabled参照）。
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

    final peerConnection = await createPeerConnection(buildRtcConfiguration());
    _peerConnections[otherUserId] = peerConnection;
    _remoteDescriptionSet[otherUserId] = false;
    _pendingRemoteCandidates[otherUserId] = [];
    _appliedCandidateKeys[otherUserId] = {};

    for (final track in _localStream!.getTracks()) {
      await peerConnection.addTrack(track, _localStream!);
    }

    peerConnection.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        renderer.srcObject = event.streams.first;
      }
    };

    peerConnection.onIceConnectionState = (iceState) {
      final issue = iceState == RTCIceConnectionState.RTCIceConnectionStateFailed ||
          iceState == RTCIceConnectionState.RTCIceConnectionStateDisconnected;
      if (peerConnectionIssues[otherUserId] != issue) {
        peerConnectionIssues[otherUserId] = issue;
        notifyListeners();
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
        _applyOrBufferCandidate(otherUserId, peerConnection, data);
      }
    });

    await _repository.initiatePeerLink(
      groupCallId: groupCallId,
      userAId: currentUser.userId,
      userBId: otherUserId,
    );

    // peerLinkのoffer/answerは初回接続時の1回だけでなく、通話中の音声⇔
    // ビデオ切替（setVideoEnabled/_reconcileGroupVideoTo参照）のたびに
    // 上書きされる。「新着かどうか」はSDP文字列の差分で判定し、自分が
    // 直前に送った値でも既に適用済みの値でもない場合だけ相手からの新規
    // オファー/アンサーとして扱う。初回接続時のオファー役（userA/userB）は
    // 同時オファーによる衝突を避けるための決め事に過ぎず、通話中の再
    // ネゴシエーションはどちらの役割からでも開始できる。
    _peerLinkSubs[otherUserId] = _repository
        .watchPeerLink(groupCallId: groupCallId, pairId: pairId)
        .listen((link) async {
      if (link == null) return;

      final offerSdp = link.offer?['sdp'] as String?;
      if (offerSdp != null &&
          offerSdp != _pendingLocalOfferSdp[otherUserId] &&
          offerSdp != _lastAppliedOfferSdp[otherUserId]) {
        _lastAppliedOfferSdp[otherUserId] = offerSdp;
        await _applyRemotePeerOffer(otherUserId, peerConnection, link.offer!);
      }

      final answerSdp = link.answer?['sdp'] as String?;
      if (answerSdp != null &&
          answerSdp != _pendingLocalAnswerSdp[otherUserId] &&
          answerSdp != _lastAppliedAnswerSdp[otherUserId]) {
        _lastAppliedAnswerSdp[otherUserId] = answerSdp;
        await peerConnection.setRemoteDescription(
          RTCSessionDescription(answerSdp, link.answer!['type'] as String),
        );
        _flushPendingCandidates(otherUserId, peerConnection);
      }
    });

    if (isUserA) {
      await _createAndSendPeerOffer(otherUserId, peerConnection);
    }
  }

  Future<void> _applyRemotePeerOffer(
    String otherUserId,
    RTCPeerConnection peerConnection,
    Map<String, dynamic> offerMap,
  ) async {
    await peerConnection.setRemoteDescription(
      RTCSessionDescription(offerMap['sdp'] as String, offerMap['type'] as String),
    );
    _flushPendingCandidates(otherUserId, peerConnection);
    final answer = await peerConnection.createAnswer();
    await peerConnection.setLocalDescription(answer);
    _pendingLocalAnswerSdp[otherUserId] = answer.sdp;
    await _repository.setPeerAnswer(
      groupCallId: groupCallId,
      pairId: CallPeerLink.idFor(currentUser.userId, otherUserId),
      answer: {'sdp': answer.sdp, 'type': answer.type},
    );
  }

  Future<void> _createAndSendPeerOffer(
    String otherUserId,
    RTCPeerConnection peerConnection,
  ) async {
    final offer = await peerConnection.createOffer();
    await peerConnection.setLocalDescription(offer);
    _pendingLocalOfferSdp[otherUserId] = offer.sdp;
    await _repository.setPeerOffer(
      groupCallId: groupCallId,
      pairId: CallPeerLink.idFor(currentUser.userId, otherUserId),
      offer: {'sdp': offer.sdp, 'type': offer.type},
    );
  }

  void _applyOrBufferCandidate(
    String otherUserId,
    RTCPeerConnection peerConnection,
    Map<String, dynamic> data,
  ) {
    final key = '${data['candidate']}|${data['sdpMid']}|${data['sdpMLineIndex']}';
    final appliedKeys = _appliedCandidateKeys[otherUserId] ??= {};
    if (appliedKeys.contains(key)) return;
    if (_remoteDescriptionSet[otherUserId] != true) {
      (_pendingRemoteCandidates[otherUserId] ??= []).add(data);
      return;
    }
    appliedKeys.add(key);
    peerConnection
        .addCandidate(
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

  void _flushPendingCandidates(
    String otherUserId,
    RTCPeerConnection peerConnection,
  ) {
    _remoteDescriptionSet[otherUserId] = true;
    final pending = [...?_pendingRemoteCandidates[otherUserId]];
    _pendingRemoteCandidates[otherUserId]?.clear();
    for (final data in pending) {
      _applyOrBufferCandidate(otherUserId, peerConnection, data);
    }
  }

  void _disconnectFromPeer(String otherUserId) {
    _peerLinkSubs.remove(otherUserId)?.cancel();
    _peerCandidateSubs.remove(otherUserId)?.cancel();
    _peerConnections.remove(otherUserId)?.close();
    remoteRenderers.remove(otherUserId)?.dispose();
    _remoteDescriptionSet.remove(otherUserId);
    _pendingRemoteCandidates.remove(otherUserId);
    _appliedCandidateKeys.remove(otherUserId);
    _pendingLocalOfferSdp.remove(otherUserId);
    _pendingLocalAnswerSdp.remove(otherUserId);
    _lastAppliedOfferSdp.remove(otherUserId);
    _lastAppliedAnswerSdp.remove(otherUserId);
    peerConnectionIssues.remove(otherUserId);
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

  /// 通話中に音声通話⇔ビデオ通話を切り替える（1対1の
  /// `WebrtcCallController.setVideoEnabled`と同じ考え方）。メッシュ型P2Pの
  /// ため、現在つながっている全てのピアに対して個別に映像トラックの追加/
  /// 削除と再ネゴシエーション（新しいオファー送信）を行う。切り替えは
  /// 自分側にのみ適用され、他の参加者の映像トラックには一切触れない
  /// （相手はCallParticipant.isVideoの変化をUI表示にのみ使う）。
  Future<void> setVideoEnabled(bool enabled) async {
    if (enabled == _isVideo || _switchingCallType) return;
    _switchingCallType = true;
    notifyListeners();
    try {
      await _repository.updateParticipantState(
        groupCallId: groupCallId,
        userId: currentUser.userId,
        isVideo: enabled,
      );
      await _reconcileGroupVideoTo(enabled);
    } catch (_) {
      // ネットワーク瞬断等。ボタンを再度有効にし、ユーザーに再試行させる。
    } finally {
      _switchingCallType = false;
      notifyListeners();
    }
  }

  /// 自分の映像トラックの有無を[target]に合わせ、現在つながっている
  /// 全ピアに対して新しいオファーを送って再ネゴシエーションする
  /// （[setVideoEnabled]からのみ呼ばれる）。
  Future<void> _reconcileGroupVideoTo(bool target) async {
    if (target == _isVideo) return;
    if (target) {
      await _enableLocalVideoTrackForAllPeers();
    } else {
      await _disableLocalVideoTrackForAllPeers();
    }
    _isVideo = target;
    notifyListeners();
    for (final entry in _peerConnections.entries) {
      await _createAndSendPeerOffer(entry.key, entry.value);
    }
  }

  Future<void> _enableLocalVideoTrackForAllPeers() async {
    if (_localStream?.getVideoTracks().isEmpty ?? true) {
      final videoStream = await navigator.mediaDevices.getUserMedia({
        'audio': false,
        'video': buildVideoConstraints(),
      });
      _localStream?.addTrack(videoStream.getVideoTracks().first);
    }
    if (!_localRendererInitialized) {
      await localRenderer.initialize();
      _localRendererInitialized = true;
    }
    localRenderer.srcObject = _localStream;
    final track = _localStream!.getVideoTracks().first;
    for (final pc in _peerConnections.values) {
      await pc.addTrack(track, _localStream!);
    }
  }

  Future<void> _disableLocalVideoTrackForAllPeers() async {
    final videoTracks = [...?_localStream?.getVideoTracks()];
    for (final pc in _peerConnections.values) {
      final senders = await pc.getSenders();
      for (final sender in senders) {
        if (sender.track?.kind == 'video') {
          await pc.removeTrack(sender);
        }
      }
    }
    for (final track in videoTracks) {
      _localStream?.removeTrack(track);
      await track.stop();
    }
    localRenderer.srcObject = null;
    _cameraOff = false;
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
