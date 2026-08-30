import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../models/app_user.dart';
import '../../models/app_ui_style.dart';
import '../../providers/app_ui_style_provider.dart';
import '../../providers/camera_availability_provider.dart';
import '../../providers/chat_navigation_providers.dart';
import '../../providers/home_shell_providers.dart';
import '../../providers/repository_providers.dart';
import '../../router/app_router.dart';
import '../../theme/gekiga/gekiga_colors.dart';
import '../../theme/gekiga/gekiga_shapes.dart';
import '../../theme/glass/glass_colors.dart';
import '../../utils/platform_info.dart';
import '../../widgets/gekiga/gekiga_badge.dart';
import '../../widgets/gekiga/monochrome_box.dart';
import '../../widgets/glass/glass_surface.dart';
import 'active_call_session.dart';
import 'call_avatar.dart';
import 'camera_availability.dart';

/// 通話中、その会話の画面を見ていない間だけ表示する右上固定のミニ表示
/// （2026-08-19追加）。`HomeScreen`の外側`Stack`（ナビチップと同じ階層）に
/// 常時マウントしておくことで、身だしなみ・設定タブへ移動しても消えない
/// （語らいタブでその会話自体を表示中の場合は`EmbeddedCallPane`が
/// 埋め込み表示を出すため、ここでは重複を避けて非表示にする）。
///
/// 表示条件: PCではその会話を見ていない間、モバイルでは全画面から下
/// スワイプでドックした間だけ表示する。音声のみの通話も（当初は完全非表示
/// だったが）ビデオ通話と同様に表示する（2026-08-19変更）。映像が無い間は
/// 通話画面の音声通話時と同じ、呼び名の頭文字を乗せた丸いアバターを中央に
/// 表示する（[_PinnedCallBubble]参照）。
class PinnedCallOverlay extends ConsumerWidget {
  const PinnedCallOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(activeCallSessionProvider);
    if (session == null) return const SizedBox.shrink();

    final viewedConversation = ref.watch(activeConversationProvider);
    final onTalksTab = ref.watch(homeSelectedTabProvider) == kTalksTabIndex;
    final embeddedElsewhere =
        !isMobileCallPlatform &&
        onTalksTab &&
        viewedConversation == session.conversation;
    if (embeddedElsewhere) return const SizedBox.shrink();

    if (isMobileCallPlatform && !session.minimized) {
      return const SizedBox.shrink(); // まだ全画面表示中
    }

    // ミュート・映像有無等、コントローラーの状態変化に応じて
    // `_PinnedCallBubble`（マイク/映像アイコンや映像表示）を再描画する
    // ためlistenする。サイズは音声・映像とも常に固定（2026-08-21に映像
    // ありだけ画面下端まで伸ばす仕様にしたが、140幅の極端な縦長比率に
    // 横長のWebカメラ映像を詰め込むと不自然に間延びして見えるとの指摘を
    // 受け、2026-08-30に音声通話と同じ固定サイズへ戻した）。
    return ListenableBuilder(
      listenable: session.controllerListenable,
      builder: (context, _) {
        return Positioned(
          top: 8,
          right: 8,
          child: _PinnedCallBubble(session: session),
        );
      },
    );
  }
}

/// この通話セッションで中央に表示すべき映像（相手優先、無ければ自分）。
/// nullなら映像が無く、[_PinnedCallBubble]はアバターのプレースホルダーを
/// 表示する。
RTCVideoRenderer? pickCallRenderer(ActiveCallSession session) {
  switch (session) {
    case OneToOneCallSession(:final controller):
      if (controller.remoteIsVideo) return controller.remoteRenderer;
      if (controller.isVideo) return controller.localRenderer;
      return null;
    case GroupCallSession(:final controller):
      final pinned = controller.pinnedParticipant;
      if (pinned != null) return controller.remoteRenderers[pinned.userId];
      if (controller.isVideo) return controller.localRenderer;
      return null;
  }
}

class _PinnedCallBubble extends ConsumerWidget {
  const _PinnedCallBubble({required this.session});

  final ActiveCallSession session;

  /// 映像が無い間（音声のみの通話、またはビデオ通話でも相手・自分どちらも
  /// 映像を出していない間）に中央へ表示するアバター情報（userId・rhingId・
  /// 会話id）。通話画面の音声通話時（`CallScreen._audioBody`/
  /// `GroupCallScreen._audioBody`）と同じ[CallParticipantAvatar]を、
  /// 代表1人分だけ小さく表示する（2026-08-19追加、音声通話でもミニ表示を
  /// 出すようにした際に追加）。
  ({String userId, String rhingId, String? conversationId}) _placeholderInfo() {
    switch (session) {
      case OneToOneCallSession(:final call, :final currentUserId):
        return (
          userId: call.otherUserId(currentUserId),
          rhingId: call.otherRhingId(currentUserId),
          conversationId: call.dmId,
        );
      case GroupCallSession(:final controller, :final groupId):
        final remoteRepresentative = controller.remoteParticipants.firstOrNull;
        return (
          userId: remoteRepresentative?.userId ?? controller.currentUser.userId,
          rhingId:
              remoteRepresentative?.rhingId ?? controller.currentUser.rhingId,
          conversationId: groupId,
        );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final renderer = pickCallRenderer(session);
    final placeholder = _placeholderInfo();
    final muted = switch (session) {
      OneToOneCallSession(:final controller) => controller.muted,
      GroupCallSession(:final controller) => controller.muted,
    };
    final isVideo = switch (session) {
      OneToOneCallSession(:final controller) => controller.isVideo,
      GroupCallSession(:final controller) => controller.isVideo,
    };
    final switchingCallType = switch (session) {
      OneToOneCallSession(:final controller) => controller.switchingCallType,
      GroupCallSession(:final controller) => controller.switchingCallType,
    };
    // 表示中の映像が自分のものなら、前面カメラの時だけ左右反転させる
    // （2026-08-30追加、通話画面（call_screen.dart等）と同じ考え方。
    // 背面カメラの映像まで反転すると実際の景色と左右が逆になり不自然）。
    final localRenderer = switch (session) {
      OneToOneCallSession(:final controller) => controller.localRenderer,
      GroupCallSession(:final controller) => controller.localRenderer,
    };
    final isFrontCamera = switch (session) {
      OneToOneCallSession(:final controller) => controller.isFrontCamera,
      GroupCallSession(:final controller) => controller.isFrontCamera,
    };
    final mirror = renderer == localRenderer && isFrontCamera;
    final cameraAvailability =
        ref.watch(cameraAvailabilityProvider).value ??
        CameraAvailability.unknown;
    final videoToggleVisible =
        cameraAvailability != CameraAvailability.unavailable;
    final uiStyle = ref.watch(appUiStyleProvider);
    final isGekiga = uiStyle == AppUiStyle.gekiga;
    final isGlass = uiStyle == AppUiStyle.glass;

    final content = Stack(
      fit: StackFit.expand,
      children: [
        if (renderer != null)
          RTCVideoView(
            key: ObjectKey(renderer),
            renderer,
            mirror: mirror,
            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
          )
        else
          Center(
            child: CallParticipantAvatar(
              userId: placeholder.userId,
              rhingId: placeholder.rhingId,
              conversationId: placeholder.conversationId,
              radius: 36,
              fontSize: 28,
            ),
          ),
        // 通話画面（CallControlBar）と同じ相対順序（マイク→カメラ→
        // 切断）で1本の行にまとめ、映像領域の下端に浮かせる
        // （2026-08-20追加）。以前は切断を右上・マイクを左下に散らして
        // いたが、通話画面と並びを揃えるために統一した。
        Positioned(
          left: 8,
          right: 8,
          bottom: 8,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _MiniIconButton(
                icon: muted ? Icons.mic_off : Icons.mic,
                color: isGekiga || isGlass ? Colors.grey[700]! : Colors.black54,
                isGekiga: isGekiga,
                isGlass: isGlass,
                onTap: () {
                  switch (session) {
                    case OneToOneCallSession(:final controller):
                      controller.toggleMute();
                    case GroupCallSession(:final controller):
                      controller.toggleMute();
                  }
                },
              ),
              _MiniIconButton(
                icon: isVideo ? Icons.videocam : Icons.videocam_off,
                color: isGekiga || isGlass ? Colors.grey[700]! : Colors.black54,
                isGekiga: isGekiga,
                isGlass: isGlass,
                enabled: !switchingCallType,
                visible: videoToggleVisible,
                onTap: () {
                  switch (session) {
                    case OneToOneCallSession(:final controller):
                      controller.setVideoEnabled(!controller.isVideo);
                    case GroupCallSession(:final controller):
                      controller.setVideoEnabled(!controller.isVideo);
                  }
                },
              ),
              _MiniIconButton(
                icon: Icons.call_end,
                color: Colors.red,
                isGekiga: isGekiga,
                isGlass: isGlass,
                onTap: () =>
                    ref.read(activeCallSessionProvider.notifier).endCall(),
              ),
            ],
          ),
        ),
      ],
    );

    final bubbleSize = SizedBox(width: 140, height: 200, child: content);

    if (isGekiga) {
      // 通話画面のCallControlBar/CallRoundButtonと同じく、劇画スタイルの
      // 「黒外枠→白内枠」のモノクロボックス（GekigaPhotoFrameと同じ部品）で
      // 縁取る。丸角・Material elevationの影は劇画の他要素同様に使わない
      // （2026-08-30修正、新規追加時に劇画・ガラス対応のスイープから漏れて
      // いた）。
      return GestureDetector(
        onTap: () => _reopen(context, ref),
        child: SizedBox(
          width: 140,
          height: 200,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final height = constraints.maxHeight;
              // マイク・カメラ・切断ボタンを矩形前提の絶対配置（Positioned）
              // で内部に置くため、既定の非対称な斜めカット（topLeft等）は
              // 使わず、四隅とも直角の矩形にする（2026-08-30修正、既定形状
              // のままだとボタン行の端が斜めカット部分にかかって隠れて
              // いた）。
              final vertices = monochromeBoxVertices(
                width,
                height,
                topLeft: false,
                topRight: false,
                bottomRight: false,
                bottomLeft: false,
              );
              return Stack(
                fit: StackFit.expand,
                children: [
                  CustomPaint(
                    painter: MonochromeBoxPainter(
                      vertices: vertices,
                      thicknessBase: width < height ? width : height,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(6),
                    child: ClipPath(
                      clipper: MonochromeBoxClipper(
                        vertices: monochromeBoxVertices(
                          width - 12,
                          height - 12,
                          topLeft: false,
                          topRight: false,
                          bottomRight: false,
                          bottomLeft: false,
                        ),
                      ),
                      child: ColoredBox(
                        color: GekigaColors.panel,
                        child: content,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      );
    }

    if (isGlass) {
      // 他の浮遊ポップアップ・ダイアログと同じ`GlassVariant.floating`で
      // 縁の光る線を出す（2026-08-30追加、新規追加時に劇画対応と同時に
      // 対応すべきだったガラス対応漏れ）。
      return GlassSurface(
        variant: GlassVariant.floating,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(onTap: () => _reopen(context, ref), child: bubbleSize),
      );
    }

    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      color: Colors.grey.shade900,
      child: InkWell(onTap: () => _reopen(context, ref), child: bubbleSize),
    );
  }

  void _reopen(BuildContext context, WidgetRef ref) {
    if (isMobileCallPlatform) {
      // ドック中なら全画面へ戻す（同じセッションへ再アタッチする経路は
      // 各画面のinitStateが冪等に処理するため、Argsの中身は起動時と同じ
      // 形で渡せば良い）。
      ref.read(activeCallSessionProvider.notifier).setMinimized(false);
      final router = ref.read(goRouterProvider);
      switch (session) {
        case OneToOneCallSession(
          :final call,
          :final isCaller,
          :final currentUserId,
        ):
          router.push(
            '/call',
            extra: CallArgs(
              call: call,
              isCaller: isCaller,
              currentUserId: currentUserId,
            ),
          );
        case GroupCallSession(
          :final controller,
          :final groupCallId,
          :final groupId,
        ):
          router.push(
            '/group-call',
            extra: GroupCallArgs(
              groupCallId: groupCallId,
              groupId: groupId,
              currentUser: controller.currentUser,
              isVideo: controller.isVideo,
            ),
          );
      }
      return;
    }

    // PCでは全画面ルートへは戻らず、語らいタブへ切り替えた上でその会話を
    // 開く。開けば`EmbeddedCallPane`が自動的に埋め込み表示へ差し替える
    // （2026-08-19追加）。
    ref.read(homeSelectedTabProvider.notifier).set(kTalksTabIndex);
    switch (session) {
      case OneToOneCallSession(:final call):
        final caller = AppUser(
          userId: call.callerId,
          rhingId: call.callerRhingId,
        );
        final callee = AppUser(
          userId: call.calleeId,
          rhingId: call.calleeRhingId,
        );
        ref
            .read(directMessageRepositoryProvider)
            .getOrCreateDirectMessage(caller, callee)
            .then((dm) {
              ref.read(pendingDmSelectionProvider.notifier).set(dm);
            });
      case GroupCallSession(:final groupId):
        ref.read(groupRepositoryProvider).getGroup(groupId).then((group) {
          if (group != null) {
            ref.read(pendingGroupSelectionProvider.notifier).set(group);
          }
        });
    }
  }
}

class _MiniIconButton extends StatelessWidget {
  const _MiniIconButton({
    required this.icon,
    required this.color,
    required this.isGekiga,
    required this.isGlass,
    required this.onTap,
    this.enabled = true,
    this.visible = true,
  });

  final IconData icon;
  final Color color;
  final bool isGekiga;
  final bool isGlass;
  final VoidCallback onTap;

  /// タップを一時的に無効化する（枠は残したまま暗く表示、
  /// `call_controls.dart`の`CallRoundButton`のenabled/disabled表現の簡易版）。
  final bool enabled;

  /// falseの場合、`CallControlBar`の`_maybeHidden`と同じく枠のスペースだけ
  /// 残して見た目とタップ判定を消す（アイコン行の並びが動かないようにする
  /// ため）。
  final bool visible;

  @override
  Widget build(BuildContext context) {
    // 劇画スタイルは`CallRoundButton`の劇画分岐と同じ`GekigaBadgeShape`
    // （手描き風モノクロボックス）、ガラススタイルは同じく`CallRoundButton`の
    // ガラス分岐と同じ`GlassSurface`の円形パネルに切り替える（2026-08-30
    // 追加、新規追加時にどちらの対応スイープからも漏れていた）。
    final Widget button;
    if (isGekiga) {
      button = Opacity(
        opacity: enabled ? 1 : 0.4,
        child: SizedBox(
          width: 28,
          height: 28,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: enabled ? onTap : null,
              child: GekigaBadgeShape(
                color: color,
                seed: icon.hashCode,
                child: Icon(icon, color: GekigaColors.onPanel, size: 14),
              ),
            ),
          ),
        ),
      );
    } else if (isGlass) {
      button = Opacity(
        opacity: enabled ? 1 : 0.4,
        child: SizedBox(
          width: 28,
          height: 28,
          child: GlassSurface(
            variant: GlassVariant.card,
            opaque: true,
            borderRadius: BorderRadius.circular(14),
            child: Material(
              color: Colors.transparent,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: enabled ? onTap : null,
                child: Center(
                  child: Icon(
                    icon,
                    color: GlassColors.adaptiveIconColor(
                      color,
                      Theme.of(context).brightness,
                    ),
                    size: 16,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    } else {
      button = Material(
        color: enabled ? color : Colors.black26,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: enabled ? onTap : null,
          child: SizedBox(
            width: 28,
            height: 28,
            child: Icon(icon, color: Colors.white, size: 16),
          ),
        ),
      );
    }
    if (visible) return button;
    return IgnorePointer(child: Opacity(opacity: 0, child: button));
  }
}
