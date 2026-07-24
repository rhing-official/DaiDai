import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../models/call.dart';
import '../../providers/repository_providers.dart';
import 'call_controls.dart';
import 'webrtc_call_controller.dart';

/// 音声・ビデオ通話画面（発信中・着信中・通話中を1画面でまとめて扱う）。
/// 一対（1対1）限定。`call.isVideo`で音声のみ／ビデオを切り替える。
/// TURN未導入のためSTUNのみで接続する。
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

  @override
  void initState() {
    super.initState();
    _controller = WebrtcCallController(
      call: widget.call,
      isCaller: widget.isCaller,
      callRepository: ref.read(callRepositoryProvider),
    );
    _controller.addListener(_onControllerChanged);
    _controller.initialize();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    setState(() {});
    if (_controller.state == CallConnectionState.ended) {
      // 相手の切断・自分の切断どちらでも、少し見せてから画面を閉じる。
      Future.delayed(const Duration(milliseconds: 400), () {
        if (mounted) Navigator.of(context).pop();
      });
    }
  }

  @override
  void dispose() {
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

  bool get _isVideo => widget.call.isVideo;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _controller.hangUp();
      },
      child: Scaffold(
        backgroundColor: _isVideo ? Colors.black : colorScheme.surface,
        body: _isVideo ? _videoBody(colorScheme) : _audioBody(colorScheme),
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

    return Stack(
      children: [
        Positioned.fill(
          child: RTCVideoView(
            _controller.remoteRenderer,
            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
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
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        width: 90,
                        height: 130,
                        color: Colors.grey.shade900,
                        child: _controller.cameraOff
                            ? const Icon(
                                Icons.videocam_off,
                                color: Colors.white54,
                              )
                            : RTCVideoView(
                                _controller.localRenderer,
                                mirror: true,
                                objectFit: RTCVideoViewObjectFit
                                    .RTCVideoViewObjectFitCover,
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
          // flutter_webrtcのSDPネゴシエーションは_startAsCallee内で自動的に
          // 開始されるため、「応答」は見た目上の待機表示のみで機能的な操作は不要。
          const CallRoundButton(icon: Icons.call, color: Colors.green, onPressed: null),
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
        if (_isVideo)
          CallRoundButton(
            icon: _controller.cameraOff
                ? Icons.videocam_off
                : Icons.videocam,
            color: Colors.grey[700]!,
            onPressed: isActive ? _controller.toggleCamera : null,
          ),
        CallRoundButton(
          icon: Icons.call_end,
          color: Colors.red,
          onPressed: _controller.hangUp,
        ),
      ],
    );
  }
}
