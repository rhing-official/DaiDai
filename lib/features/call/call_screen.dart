import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../models/call.dart';
import '../../providers/repository_providers.dart';
import 'webrtc_call_controller.dart';

/// 音声通話画面（発信中・着信中・通話中を1画面でまとめて扱う）。
/// フェーズ1は音声のみ・一対（1対1）限定。TURN未導入のためSTUNのみで接続する。
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

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _controller.hangUp();
      },
      child: Scaffold(
        backgroundColor: colorScheme.surface,
        body: SafeArea(
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
        ),
      ),
    );
  }

  Widget _controls(ColorScheme colorScheme) {
    final isRinging = _controller.state == CallConnectionState.connecting;

    if (isRinging && !widget.isCaller) {
      // 着信中: 拒否・応答の2択。
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _RoundButton(
            icon: Icons.call_end,
            color: Colors.red,
            onPressed: _controller.decline,
          ),
          // flutter_webrtcのSDPネゴシエーションは_startAsCallee内で自動的に
          // 開始されるため、「応答」は見た目上の待機表示のみで機能的な操作は不要。
          const _RoundButton(icon: Icons.call, color: Colors.green, onPressed: null),
        ],
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _RoundButton(
          icon: _controller.muted ? Icons.mic_off : Icons.mic,
          color: Colors.grey[700]!,
          onPressed: _controller.state == CallConnectionState.active
              ? _controller.toggleMute
              : null,
        ),
        _RoundButton(
          icon: Icons.call_end,
          color: Colors.red,
          onPressed: _controller.hangUp,
        ),
      ],
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.color, this.onPressed});

  final IconData icon;
  final Color color;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      heroTag: null,
      backgroundColor: onPressed == null ? Colors.grey[300] : color,
      onPressed: onPressed,
      child: Icon(icon, color: Colors.white),
    );
  }
}
