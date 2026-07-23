import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../models/call.dart';
import '../../repositories/call_repository.dart';

enum CallConnectionState { connecting, active, ended }

/// STUNサーバーのみを使う（TURNはフェーズ1未導入。CLAUDE.md参照）。
/// 双方が対称NAT配下にいるなど厳しいネットワーク環境では接続できないことがある。
const _rtcConfiguration = {
  'iceServers': [
    {'urls': 'stun:stun.l.google.com:19302'},
  ],
};

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

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  StreamSubscription<Call?>? _callSub;
  StreamSubscription<List<Map<String, dynamic>>>? _candidatesSub;
  bool _answerApplied = false;

  CallConnectionState _state = CallConnectionState.connecting;
  CallConnectionState get state => _state;

  bool _muted = false;
  bool get muted => _muted;

  String? _error;
  String? get error => _error;

  Future<void> initialize() async {
    try {
      await remoteRenderer.initialize();

      // ブラウザ/ネイティブWebRTCスタックに標準搭載のノイズ抑制・エコー除去・
      // 自動ゲイン調整を明示的に要求する。本格的なRNNoise統合は、
      // flutter_webrtc/libwebrtcがマイク→エンコーダ間の生音声サンプルに
      // 介入するフックをDart層に公開しておらず、プラットフォームごとの
      // ネイティブ音声パイプライン改造が必要な大規模な別プロジェクトになるため、
      // 現時点ではここでの標準ノイズ抑制のみを実装している（詳細は会話参照）。
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        },
        'video': false,
      });

      _peerConnection = await createPeerConnection(_rtcConfiguration);
      for (final track in _localStream!.getAudioTracks()) {
        await _peerConnection!.addTrack(track, _localStream!);
      }

      _peerConnection!.onTrack = (event) {
        if (event.streams.isNotEmpty) {
          remoteRenderer.srcObject = event.streams.first;
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
          _peerConnection?.addCandidate(
            RTCIceCandidate(
              data['candidate'] as String,
              data['sdpMid'] as String?,
              data['sdpMLineIndex'] as int?,
            ),
          );
        }
      });

      if (isCaller) {
        await _startAsCaller();
      } else {
        await _startAsCallee();
      }
    } catch (e) {
      _error = '通話を開始できませんでした（マイクの利用を許可してください）: $e';
      _state = CallConnectionState.ended;
      notifyListeners();
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
        _state = CallConnectionState.active;
        notifyListeners();
      }
    });
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
    final answer = await _peerConnection!.createAnswer();
    await _peerConnection!.setLocalDescription(answer);
    await _callRepository.setAnswer(call.callId, {
      'sdp': answer.sdp,
      'type': answer.type,
    });

    _state = CallConnectionState.active;
    notifyListeners();

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

  @override
  void dispose() {
    _callSub?.cancel();
    _candidatesSub?.cancel();
    for (final track in _localStream?.getTracks() ?? <MediaStreamTrack>[]) {
      track.stop();
    }
    _localStream?.dispose();
    _peerConnection?.close();
    remoteRenderer.dispose();
    super.dispose();
  }
}
