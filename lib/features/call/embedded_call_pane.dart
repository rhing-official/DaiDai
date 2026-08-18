import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../models/app_ui_style.dart';
import '../../providers/app_ui_style_provider.dart';
import '../../providers/camera_availability_provider.dart';
import '../../providers/chat_navigation_providers.dart';
import '../../utils/platform_info.dart';
import 'active_call_session.dart';
import 'call_avatar.dart';
import 'call_control_bar.dart';
import 'camera_availability.dart';
import 'webrtc_call_controller.dart';
import 'webrtc_group_call_controller.dart';

/// PC/Web限定: 通話中の会話画面で、メッセージ一覧の代わりに通話UIを
/// 埋め込み表示する（2026-08-19追加、通話UIの再設計に伴う）。
/// `DmChatPane`/`GroupChatPane`が[child]（通常のチャット画面）をこれで
/// 包み、[conversation]に一致する通話セッションが存在しPC/Webである間だけ
/// 通話UIへ差し替える。マウント中は`activeConversationProvider`へ自分の
/// 会話を報告し（`PinnedCallOverlay`が「今その会話を見ているか」を
/// 判定するのに使う）、アンマウント時にクリアする。
class EmbeddedCallPane extends ConsumerStatefulWidget {
  const EmbeddedCallPane({
    required this.conversation,
    required this.conversationTitle,
    required this.child,
    super.key,
  });

  final ViewedConversation conversation;
  final String conversationTitle;
  final Widget child;

  @override
  ConsumerState<EmbeddedCallPane> createState() => _EmbeddedCallPaneState();
}

class _EmbeddedCallPaneState extends ConsumerState<EmbeddedCallPane> {
  /// 通話UIとメッセージ一覧、どちらを表示中か（通話中のみ意味を持つ
  /// トグル、`_Header`の「メッセージに戻る」ボタンで切り替える）。
  bool _showingCall = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _report());
  }

  @override
  void didUpdateWidget(covariant EmbeddedCallPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.conversation != widget.conversation) {
      _showingCall = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _report());
    }
  }

  void _report() {
    if (!mounted) return;
    ref.read(activeConversationProvider.notifier).set(widget.conversation);
  }

  @override
  void dispose() {
    ref
        .read(activeConversationProvider.notifier)
        .clearIfCurrent(widget.conversation);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(activeCallSessionProvider);
    final isMatch =
        !isMobileCallPlatform &&
        session != null &&
        session.conversation == widget.conversation;

    if (!isMatch) return widget.child;

    if (!_showingCall) {
      return Stack(
        children: [
          widget.child,
          Positioned(
            top: 8,
            left: 0,
            right: 0,
            child: Center(
              child: _ReturnToCallChip(
                onTap: () => setState(() => _showingCall = true),
              ),
            ),
          ),
        ],
      );
    }

    return _EmbeddedCallView(
      session: session,
      title: widget.conversationTitle,
      onBackToMessages: () => setState(() => _showingCall = false),
    );
  }
}

/// メッセージ表示に切り替えた後も、通話中であることと戻る導線を示す
/// 小さなチップ。
class _ReturnToCallChip extends StatelessWidget {
  const _ReturnToCallChip({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black87,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.call, color: Colors.white, size: 16),
              SizedBox(width: 8),
              Text('通話中 - タップして戻る', style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmbeddedCallView extends StatelessWidget {
  const _EmbeddedCallView({
    required this.session,
    required this.title,
    required this.onBackToMessages,
  });

  final ActiveCallSession session;
  final String title;
  final VoidCallback onBackToMessages;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: session.controllerListenable,
      builder: (context, _) {
        return ColoredBox(
          color: Colors.black,
          child: Column(
            children: [
              _Header(title: title, onBackToMessages: onBackToMessages),
              Expanded(
                child: switch (session) {
                  OneToOneCallSession s => _OneToOneStage(session: s),
                  GroupCallSession s => _GroupStage(session: s),
                },
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: _EmbeddedControls(session: session),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title, required this.onBackToMessages});
  final String title;
  final VoidCallback onBackToMessages;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.expand_more, color: Colors.white),
              tooltip: 'メッセージに戻る',
              onPressed: onBackToMessages,
            ),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OneToOneStage extends StatelessWidget {
  const _OneToOneStage({required this.session});
  final OneToOneCallSession session;

  @override
  Widget build(BuildContext context) {
    final controller = session.controller;
    if (!controller.remoteIsVideo && !controller.isVideo) {
      return Center(
        child: CallParticipantAvatar(
          userId: session.call.otherUserId(session.currentUserId),
          rhingId: session.call.otherRhingId(session.currentUserId),
          conversationId: session.call.dmId,
          radius: 56,
          fontSize: 40,
        ),
      );
    }
    return Stack(
      children: [
        Positioned.fill(
          child: controller.remoteIsVideo
              ? RTCVideoView(
                  key: ObjectKey(controller.remoteRenderer),
                  controller.remoteRenderer,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                )
              : const ColoredBox(color: Color(0xFF212121)),
        ),
        if (controller.isVideo)
          Positioned(
            right: 12,
            bottom: 12,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 80,
                height: 110,
                child: RTCVideoView(
                  key: ObjectKey(controller.localRenderer),
                  controller.localRenderer,
                  mirror: true,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _GroupStage extends StatelessWidget {
  const _GroupStage({required this.session});
  final GroupCallSession session;

  @override
  Widget build(BuildContext context) {
    final controller = session.controller;
    final tiles = [
      _tile(
        userId: controller.currentUser.userId,
        rhingId: controller.currentUser.rhingId,
        renderer: controller.isVideo ? controller.localRenderer : null,
        mirror: true,
        videoEnabled: controller.isVideo,
      ),
      for (final p in controller.remoteParticipants)
        _tile(
          userId: p.userId,
          rhingId: p.rhingId,
          renderer: controller.remoteRenderers[p.userId],
          mirror: false,
          videoEnabled: p.isVideo,
        ),
    ];
    return GridView.count(
      crossAxisCount: tiles.length > 2 ? 2 : tiles.length.clamp(1, 2),
      padding: const EdgeInsets.all(4),
      mainAxisSpacing: 4,
      crossAxisSpacing: 4,
      children: tiles,
    );
  }

  Widget _tile({
    required String userId,
    required String rhingId,
    required RTCVideoRenderer? renderer,
    required bool mirror,
    required bool videoEnabled,
  }) {
    return Container(
      color: Colors.grey.shade900,
      child: videoEnabled && renderer != null
          ? RTCVideoView(
              key: ObjectKey(renderer),
              renderer,
              mirror: mirror,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
            )
          : Center(
              child: CallParticipantAvatar(
                userId: userId,
                rhingId: rhingId,
                conversationId: session.groupId,
                radius: 28,
              ),
            ),
    );
  }
}

class _EmbeddedControls extends ConsumerWidget {
  const _EmbeddedControls({required this.session});
  final ActiveCallSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isGekiga = ref.watch(appUiStyleProvider) == AppUiStyle.gekiga;
    final cameraAvailability =
        ref.watch(cameraAvailabilityProvider).value ??
        CameraAvailability.unknown;
    return switch (session) {
      OneToOneCallSession(:final controller) => CallControlBar(
        isGekiga: isGekiga,
        enabled: controller.state == CallConnectionState.active,
        muted: controller.muted,
        onToggleMute: controller.toggleMute,
        speakerOn: controller.speakerOn,
        onToggleSpeaker: controller.toggleSpeaker,
        switchingCallType: controller.switchingCallType,
        onToggleVideoType: cameraAvailability == CameraAvailability.unavailable
            ? null
            : () => controller.setVideoEnabled(!controller.isVideo),
        isVideo: controller.isVideo,
        hasMultipleCameras: controller.hasMultipleCameras,
        switchingCamera: controller.switchingCamera,
        onSwitchCamera: controller.switchCamera,
        onHangUp: controller.hangUp,
      ),
      GroupCallSession(:final controller) => CallControlBar(
        isGekiga: isGekiga,
        enabled: controller.state == GroupCallConnectionState.active,
        muted: controller.muted,
        onToggleMute: controller.toggleMute,
        speakerOn: controller.speakerOn,
        onToggleSpeaker: controller.toggleSpeaker,
        switchingCallType: controller.switchingCallType,
        onToggleVideoType: cameraAvailability == CameraAvailability.unavailable
            ? null
            : () => controller.setVideoEnabled(!controller.isVideo),
        isVideo: controller.isVideo,
        hasMultipleCameras: controller.hasMultipleCameras,
        switchingCamera: controller.switchingCamera,
        onSwitchCamera: controller.switchCamera,
        onHangUp: () => controller.leave(),
      ),
    };
  }
}
