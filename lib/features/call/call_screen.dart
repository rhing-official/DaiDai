import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../models/call.dart';
import '../../providers/repository_providers.dart';
import 'call_controls.dart';
import 'webrtc_call_controller.dart';

/// 音声・ビデオ通話画面（発信中・着信中・通話中を1画面でまとめて扱う）。
/// 一対（1対1）限定。開始時点の種別は`call.isVideo`だが、通話中に
/// [WebrtcCallController.setVideoEnabled]で音声⇔ビデオを切り替えられる
/// （`_controller.isVideo`が自分の現在の種別、`_controller.remoteIsVideo`が
/// 相手の現在の種別。切替は互いに独立しており、相手を強制的に切り替える
/// ことはない）。TURN未導入のためSTUNのみで接続する。
class CallScreen extends ConsumerStatefulWidget {
  const CallScreen({
    required this.call,
    required this.isCaller,
    required this.currentUserId,
    super.key,
  });

  final Call call;
  final bool isCaller;
  final String currentUserId;

  @override
  ConsumerState<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends ConsumerState<CallScreen> {
  late final WebrtcCallController _controller;

  /// ビデオ通話でフルスクリーン側に相手（true）/自分（false）どちらを
  /// 表示するか。タップで入れ替える。
  bool _mainViewIsRemote = true;

  @override
  void initState() {
    super.initState();
    _controller = WebrtcCallController(
      call: widget.call,
      isCaller: widget.isCaller,
      callRepository: ref.read(callRepositoryProvider),
      directMessageRepository: ref.read(directMessageRepositoryProvider),
    );
    _controller.addListener(_onControllerChanged);
    _controller.initialize();
    if (!widget.isCaller) {
      _controller.soundPlayer.startRingtoneLoop();
    }
  }

  void _onControllerChanged() {
    if (!mounted) return;
    setState(() {});
    if (_controller.state != CallConnectionState.connecting) {
      _controller.soundPlayer.stopRingtone();
    }
    if (_controller.state == CallConnectionState.ended) {
      // 相手の切断・自分の切断どちらでも、少し見せてから画面を閉じる。
      Future.delayed(const Duration(milliseconds: 400), () {
        if (mounted) Navigator.of(context).pop();
      });
    }
  }

  @override
  void dispose() {
    _controller.soundPlayer.stopRingtone();
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    super.dispose();
  }

  String get _otherRhingId => widget.call.otherRhingId(widget.currentUserId);

  String get _statusLabel {
    if (_controller.error != null) return _controller.error!;
    switch (_controller.state) {
      case CallConnectionState.connecting:
        return widget.isCaller ? '発信中…' : '接続中…';
      case CallConnectionState.active:
        return '通話中';
      case CallConnectionState.ended:
        return '通話終了';
    }
  }

  /// 自分が現在ビデオ通話として動作しているか。
  bool get _myIsVideo => _controller.isVideo;

  /// 相手が現在ビデオ通話として動作しているか。切替は互いに独立している
  /// ため、片方だけがビデオという状態もありうる（その場合、映像が無い側の
  /// 表示はカメラオフ時と同じプレースホルダーになる。_videoBody参照）。
  bool get _remoteIsVideo => _controller.remoteIsVideo;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final anyVideo = _myIsVideo || _remoteIsVideo;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _controller.hangUp();
      },
      child: Scaffold(
        backgroundColor: anyVideo ? Colors.black : colorScheme.surface,
        body: anyVideo ? _videoBody(colorScheme) : _audioBody(colorScheme),
      ),
    );
  }

  Widget _audioBody(ColorScheme colorScheme) {
    return SafeArea(
      child: Column(
        children: [
          // 音声のみの通話でもリモートの音声を再生するためにレンダラーを紐づける。
          SizedBox(
            width: 0,
            height: 0,
            child: RTCVideoView(_controller.remoteRenderer),
          ),
          const Spacer(),
          CircleAvatar(
            radius: 56,
            backgroundColor: colorScheme.primary,
            child: Text(
              _otherRhingId.isNotEmpty ? _otherRhingId[0].toUpperCase() : '?',
              style: const TextStyle(fontSize: 40, color: Colors.white),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            '@$_otherRhingId',
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(_statusLabel, style: const TextStyle(color: Colors.grey)),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.only(bottom: 48),
            child: _controls(colorScheme),
          ),
        ],
      ),
    );
  }

  /// ビデオ通話のレイアウト。相手の映像を画面全面に敷き、上部に名前・状態、
  /// 右上に自分のカメラプレビューを重ねる。相手の映像がまだ届いていない
  /// （発信中・接続中）の間は背景が黒いだけになるため、中央にアバターを重ねて
  /// 音声通話と同じように相手が誰かを常に視認できるようにする。
  Widget _videoBody(ColorScheme colorScheme) {
    final isConnected = _controller.state == CallConnectionState.active;
    final mainRenderer = _mainViewIsRemote
        ? _controller.remoteRenderer
        : _controller.localRenderer;
    final pipRenderer = _mainViewIsRemote
        ? _controller.localRenderer
        : _controller.remoteRenderer;

    // 音声⇔ビデオの切替は自分・相手それぞれ独立しているため、映像が無い側
    // （自分がビデオオフ、または相手がビデオオフ）はカメラオフ時と同じ
    // プレースホルダーで表示する。
    final mainShowsPlaceholder = _mainViewIsRemote
        ? !_remoteIsVideo
        : (!_myIsVideo || _controller.cameraOff);
    final pipShowsPlaceholder = _mainViewIsRemote
        ? (!_myIsVideo || _controller.cameraOff)
        : !_remoteIsVideo;

    void swapViews() => setState(() => _mainViewIsRemote = !_mainViewIsRemote);

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: swapViews,
            child: mainShowsPlaceholder
                ? Container(
                    color: Colors.grey.shade900,
                    child: const Center(
                      child: Icon(Icons.videocam_off,
                          color: Colors.white54, size: 48),
                    ),
                  )
                : RTCVideoView(
                    // Web版のRTCVideoViewはStatefulWidgetで、実描画に使う
                    // videoElementをinitState時にしか取得しない。keyが無いと
                    // メイン/コーナーを入れ替えてもFlutterが同じStateを使い
                    // 回してしまい、映像が入れ替わらずミラー表示だけが
                    // 切り替わって見える不具合になっていた。レンダラーの
                    // 実体が変わったら必ず作り直されるよう、レンダラー自体を
                    // キーにする。
                    key: ObjectKey(mainRenderer),
                    mainRenderer,
                    mirror: !_mainViewIsRemote,
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  ),
          ),
        ),
        if (!isConnected)
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 56,
                  backgroundColor: colorScheme.primary,
                  child: Text(
                    _otherRhingId.isNotEmpty
                        ? _otherRhingId[0].toUpperCase()
                        : '?',
                    style: const TextStyle(fontSize: 40, color: Colors.white),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  '@$_otherRhingId',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        if (isConnected && _controller.connectionIssue)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    '接続が不安定です…',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
              ),
            ),
          ),
        SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '@$_otherRhingId',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              shadows: [Shadow(blurRadius: 6)],
                            ),
                          ),
                          Text(
                            _statusLabel,
                            style: const TextStyle(
                              color: Colors.white70,
                              shadows: [Shadow(blurRadius: 6)],
                            ),
                          ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: swapViews,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          width: 90,
                          height: 130,
                          color: Colors.grey.shade900,
                          child: pipShowsPlaceholder
                              ? const Icon(
                                  Icons.videocam_off,
                                  color: Colors.white54,
                                )
                              : RTCVideoView(
                                  key: ObjectKey(pipRenderer),
                                  pipRenderer,
                                  mirror: _mainViewIsRemote,
                                  objectFit: RTCVideoViewObjectFit
                                      .RTCVideoViewObjectFitCover,
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: _controls(colorScheme),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _controls(ColorScheme colorScheme) {
    final isRinging = _controller.state == CallConnectionState.connecting;

    if (isRinging && !widget.isCaller) {
      // 着信中: 拒否・応答の2択。
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          CallRoundButton(
            icon: Icons.call_end,
            color: Colors.red,
            onPressed: _controller.decline,
          ),
          CallRoundButton(
            icon: Icons.call,
            color: Colors.green,
            onPressed: !_controller.accepting
                ? () {
                    HapticFeedback.vibrate();
                    _controller.accept();
                  }
                : null,
          ),
        ],
      );
    }

    final isActive = _controller.state == CallConnectionState.active;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        CallRoundButton(
          icon: _controller.muted ? Icons.mic_off : Icons.mic,
          color: Colors.grey[700]!,
          onPressed: isActive ? _controller.toggleMute : null,
        ),
        Tooltip(
          message: _controller.speakerOn ? 'スピーカーで再生中' : '受話口（イヤピース）で再生中',
          child: CallRoundButton(
            icon: _controller.speakerOn
                ? Icons.volume_up
                : Icons.phone_in_talk,
            color: Colors.grey[700]!,
            onPressed: isActive ? _controller.toggleSpeaker : null,
          ),
        ),
        Tooltip(
          message: _myIsVideo ? '音声通話に切り替える' : 'ビデオ通話に切り替える',
          child: CallRoundButton(
            icon: Icons.switch_video,
            color: Colors.grey[700]!,
            onPressed: isActive && !_controller.switchingCallType
                ? () => _controller.setVideoEnabled(!_myIsVideo)
                : null,
          ),
        ),
        if (_myIsVideo) ...[
          CallRoundButton(
            icon: _controller.cameraOff
                ? Icons.videocam_off
                : Icons.videocam,
            color: Colors.grey[700]!,
            onPressed: isActive ? _controller.toggleCamera : null,
          ),
          CallRoundButton(
            icon: Icons.cameraswitch,
            color: Colors.grey[700]!,
            onPressed: isActive &&
                    !_controller.cameraOff &&
                    !_controller.switchingCamera
                ? _controller.switchCamera
                : null,
          ),
        ],
        CallRoundButton(
          icon: Icons.call_end,
          color: Colors.red,
          onPressed: _controller.hangUp,
        ),
      ],
    );
  }
}
