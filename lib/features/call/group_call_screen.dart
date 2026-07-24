import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../models/app_user.dart';
import '../../providers/repository_providers.dart';
import 'call_controls.dart';
import 'webrtc_group_call_controller.dart';

/// 広場（グループ）通話画面。メッシュ型P2Pのため、参加者ごとに独立した
/// `RTCVideoRenderer`をグリッド表示する。1対1の[CallScreen]とは異なり、
/// 着信（ringing）の概念を持たず「進行中の通話に途中参加する」形になる。
class GroupCallScreen extends ConsumerStatefulWidget {
  const GroupCallScreen({
    required this.groupCallId,
    required this.currentUser,
    required this.isVideo,
    super.key,
  });

  final String groupCallId;
  final AppUser currentUser;
  final bool isVideo;

  @override
  ConsumerState<GroupCallScreen> createState() => _GroupCallScreenState();
}

class _GroupCallScreenState extends ConsumerState<GroupCallScreen> {
  late final WebrtcGroupCallController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebrtcGroupCallController(
      groupCallId: widget.groupCallId,
      currentUser: widget.currentUser,
      isVideo: widget.isVideo,
      groupCallRepository: ref.read(groupCallRepositoryProvider),
    );
    _controller.addListener(_onControllerChanged);
    _controller.initialize();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    setState(() {});
    if (_controller.state == GroupCallConnectionState.ended) {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) Navigator.of(context).pop();
      });
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _controller.leave();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _controller.leave();
      },
      child: Scaffold(
        backgroundColor: widget.isVideo ? Colors.black : null,
        body: widget.isVideo ? _videoBody() : _audioBody(),
      ),
    );
  }

  Widget _audioBody() {
    final colorScheme = Theme.of(context).colorScheme;
    final remoteParticipants = _controller.remoteParticipants;
    final tiles = [widget.currentUser.rhingId, ...remoteParticipants.map((p) => p.rhingId)];

    return SafeArea(
      child: Column(
        children: [
          // 音声のみの通話でもリモートの音声を再生するためにレンダラーを紐づける。
          SizedBox(
            width: 0,
            height: 0,
            child: Stack(
              children: [
                for (final renderer in _controller.remoteRenderers.values)
                  RTCVideoView(renderer),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text(
            '参加者${tiles.length}人',
            style: TextStyle(color: colorScheme.onSurfaceVariant),
          ),
          const Spacer(),
          Wrap(
            spacing: 24,
            runSpacing: 24,
            alignment: WrapAlignment.center,
            children: [
              for (final rhingId in tiles)
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: 40,
                      backgroundColor: colorScheme.primary,
                      child: Text(
                        rhingId.isNotEmpty ? rhingId[0].toUpperCase() : '?',
                        style: const TextStyle(fontSize: 28, color: Colors.white),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text('@$rhingId'),
                  ],
                ),
            ],
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.only(bottom: 48),
            child: _controls(),
          ),
        ],
      ),
    );
  }

  Widget _videoBody() {
    final remoteParticipants = _controller.remoteParticipants;
    final tileCount = 1 + remoteParticipants.length;

    if (tileCount == 1) {
      return SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: Text(
                  '他の参加者を待っています…',
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: _controls(),
            ),
          ],
        ),
      );
    }

    final crossAxisCount = sqrt(tileCount).ceil();

    return SafeArea(
      child: Column(
        children: [
          Expanded(
            child: GridView.count(
              crossAxisCount: crossAxisCount,
              padding: const EdgeInsets.all(4),
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
              children: [
                _videoTile(
                  rhingId: widget.currentUser.rhingId,
                  renderer: widget.isVideo ? _controller.localRenderer : null,
                  mirror: true,
                  micMuted: _controller.muted,
                  cameraOff: _controller.cameraOff,
                ),
                for (final participant in remoteParticipants)
                  _videoTile(
                    rhingId: participant.rhingId,
                    renderer: _controller.remoteRenderers[participant.userId],
                    mirror: false,
                    micMuted: participant.micMuted,
                    cameraOff: participant.cameraOff,
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: _controls(),
          ),
        ],
      ),
    );
  }

  Widget _videoTile({
    required String rhingId,
    required RTCVideoRenderer? renderer,
    required bool mirror,
    required bool micMuted,
    required bool cameraOff,
  }) {
    return Container(
      color: Colors.grey.shade900,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (!cameraOff && renderer != null)
            RTCVideoView(
              renderer,
              mirror: mirror,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
            )
          else
            Center(
              child: CircleAvatar(
                radius: 32,
                child: Text(rhingId.isNotEmpty ? rhingId[0].toUpperCase() : '?'),
              ),
            ),
          Positioned(
            left: 8,
            bottom: 8,
            child: Row(
              children: [
                if (micMuted)
                  const Padding(
                    padding: EdgeInsets.only(right: 4),
                    child: Icon(Icons.mic_off, size: 14, color: Colors.white),
                  ),
                Text(
                  '@$rhingId',
                  style: const TextStyle(
                    color: Colors.white,
                    shadows: [Shadow(blurRadius: 6)],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _controls() {
    final isActive = _controller.state == GroupCallConnectionState.active;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        CallRoundButton(
          icon: _controller.muted ? Icons.mic_off : Icons.mic,
          color: Colors.grey[700]!,
          onPressed: isActive ? _controller.toggleMute : null,
        ),
        if (widget.isVideo)
          CallRoundButton(
            icon: _controller.cameraOff ? Icons.videocam_off : Icons.videocam,
            color: Colors.grey[700]!,
            onPressed: isActive ? _controller.toggleCamera : null,
          ),
        CallRoundButton(
          icon: Icons.call_end,
          color: Colors.red,
          onPressed: () => _controller.leave(),
        ),
      ],
    );
  }
}
