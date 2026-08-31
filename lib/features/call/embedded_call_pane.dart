import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../models/app_ui_style.dart';
import '../../providers/app_ui_style_provider.dart';
import '../../providers/camera_availability_provider.dart';
import '../../providers/chat_navigation_providers.dart';
import '../../utils/platform_info.dart';
import '../../widgets/swipe_gestures.dart';
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
    required this.child,
    super.key,
  });

  final ViewedConversation conversation;
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

class _EmbeddedCallView extends StatefulWidget {
  const _EmbeddedCallView({
    required this.session,
    required this.onBackToMessages,
  });

  final ActiveCallSession session;
  final VoidCallback onBackToMessages;

  @override
  State<_EmbeddedCallView> createState() => _EmbeddedCallViewState();
}

class _EmbeddedCallViewState extends State<_EmbeddedCallView> {
  /// マウスホイール/トラックパッドでの上スクロール終了のデバウンス用
  /// タイマー（2026-08-30追加、`chat_screen.dart`のメディアビューアと同じ
  /// パターン。1回のトラックパッド操作で多数の`PointerScrollEvent`が連続
  /// して届くため、即座に[VoidCallback]を呼ぶと残りのイベントが遷移後の
  /// メッセージ一覧側へ漏れて意図せずスクロールしてしまう不具合を避ける）。
  Timer? _scrollBackTimer;

  @override
  void dispose() {
    _scrollBackTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 表示領域以外（ヘッダー・コントロール周りを含むこのパネル全体の背景）は
    // 常にテーマの背景色にする（2026-08-30更新、以前はガラスUIのみだったが
    // 3スタイル共通にした）。表示領域自体（映像 or その代役の
    // プレースホルダー）は各Stageが常に固定グレーを使う。
    final colorScheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: widget.session.controllerListenable,
      builder: (context, _) {
        // 通話画面の座標上のどこでも、左上のボタン（`_Header`の
        // `expand_more`）を押すのと同じ「メッセージに戻る」動作を、上
        // スクロール（マウスホイール/トラックパッド）・下スワイプ
        // （タッチ・マウスドラッグ）どちらからでも行えるようにする
        // （2026-08-30追加）。
        return Listener(
          onPointerSignal: (event) {
            if (event is PointerScrollEvent && event.scrollDelta.dy < -2.0) {
              _scrollBackTimer?.cancel();
              _scrollBackTimer = Timer(const Duration(milliseconds: 150), () {
                if (mounted) widget.onBackToMessages();
              });
            }
          },
          child: SwipeDownToDismiss(
            onDismiss: widget.onBackToMessages,
            child: ColoredBox(
              color: colorScheme.surface,
              child: Column(
                children: [
                  _Header(onBackToMessages: widget.onBackToMessages),
                  Expanded(
                    child: switch (widget.session) {
                      OneToOneCallSession s => _OneToOneStage(session: s),
                      GroupCallSession s => _GroupStage(session: s),
                    },
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: _EmbeddedControls(session: widget.session),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onBackToMessages});
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
              tooltip: '',
              onPressed: onBackToMessages,
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
      return ColoredBox(
        color: Colors.grey.shade900,
        child: Center(
          child: CallParticipantAvatar(
            userId: session.call.otherUserId(session.currentUserId),
            rhingId: session.call.otherRhingId(session.currentUserId),
            conversationId: session.call.dmId,
            radius: 56,
            fontSize: 40,
          ),
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
              : ColoredBox(color: Colors.grey.shade900),
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
                  mirror: controller.isFrontCamera,
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
        mirror: controller.isFrontCamera,
        videoEnabled: controller.isVideo,
        micMuted: controller.muted,
      ),
      for (final p in controller.remoteParticipants)
        _tile(
          userId: p.userId,
          rhingId: p.rhingId,
          renderer: controller.remoteRenderers[p.userId],
          mirror: false,
          videoEnabled: p.isVideo,
          micMuted: p.micMuted,
        ),
    ];
    final crossAxisCount = tiles.length > 2 ? 2 : tiles.length.clamp(1, 2);
    const spacing = 4.0;
    // `GridView.count`は`childAspectRatio`を指定しないと既定で正方形タイルに
    // なる。PCの埋め込みパネルは横幅に対して縦の表示領域が狭いことが多く、
    // 参加者が少ない間は正方形タイルが表示可能高さを超えてグリッド自体が
    // スクロールを要求してしまっていた（2026-08-31修正、「画面いっぱいに
    // 拡大する」のではなく「与えられた領域に収まるように計算する」という
    // 設計に転換する）。実際の`LayoutBuilder`の制約から逆算した
    // `childAspectRatio`を渡すことで、タイル数に関わらず常にスクロール無しで
    // 収まるようにする。
    return LayoutBuilder(
      builder: (context, constraints) {
        final rowCount = (tiles.length / crossAxisCount).ceil();
        final tileWidth =
            (constraints.maxWidth - spacing * (crossAxisCount + 1)) /
            crossAxisCount;
        final tileHeight =
            (constraints.maxHeight - spacing * (rowCount + 1)) / rowCount;
        return GridView.count(
          crossAxisCount: crossAxisCount,
          childAspectRatio: tileWidth / tileHeight,
          padding: const EdgeInsets.all(spacing),
          mainAxisSpacing: spacing,
          crossAxisSpacing: spacing,
          children: tiles,
        );
      },
    );
  }

  Widget _tile({
    required String userId,
    required String rhingId,
    required RTCVideoRenderer? renderer,
    required bool mirror,
    required bool videoEnabled,
    required bool micMuted,
  }) {
    return Container(
      color: Colors.grey.shade900,
      child: Stack(
        fit: StackFit.expand,
        children: [
          videoEnabled && renderer != null
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
          // 表示領域の左下に呼び名、ミュート中はその右隣にミュートアイコンを
          // 表示する（2026-08-31追加、`group_call_screen.dart`の
          // `_videoTile`と同じ並び順・見た目に揃える）。
          Positioned(
            left: 8,
            bottom: 8,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CallParticipantNameLabel(
                  userId: userId,
                  rhingId: rhingId,
                  conversationId: session.groupId,
                  style: const TextStyle(
                    color: Colors.white,
                    shadows: [Shadow(blurRadius: 6)],
                  ),
                ),
                if (micMuted) ...[
                  const SizedBox(width: 4),
                  const Icon(Icons.mic_off, size: 14, color: Colors.white),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmbeddedControls extends ConsumerWidget {
  const _EmbeddedControls({required this.session});
  final ActiveCallSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uiStyle = ref.watch(appUiStyleProvider);
    final isGekiga = uiStyle == AppUiStyle.gekiga;
    final isGlass = uiStyle == AppUiStyle.glass;
    final cameraAvailability =
        ref.watch(cameraAvailabilityProvider).value ??
        CameraAvailability.unknown;
    return switch (session) {
      OneToOneCallSession(:final controller) => CallControlBar(
        isGekiga: isGekiga,
        isGlass: isGlass,
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
        isGlass: isGlass,
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
