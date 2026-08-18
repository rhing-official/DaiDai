import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../models/app_user.dart';
import '../../providers/chat_navigation_providers.dart';
import '../../providers/home_shell_providers.dart';
import '../../providers/repository_providers.dart';
import '../../router/app_router.dart';
import '../../utils/platform_info.dart';
import 'active_call_session.dart';
import 'call_avatar.dart';

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

    return Positioned(
      top: 8,
      right: 8,
      child: _PinnedCallBubble(session: session),
    );
  }
}

class _PinnedCallBubble extends ConsumerWidget {
  const _PinnedCallBubble({required this.session});

  final ActiveCallSession session;

  RTCVideoRenderer? _pickRenderer() {
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
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      color: Colors.grey.shade900,
      child: InkWell(
        onTap: () => _reopen(context, ref),
        child: SizedBox(
          width: 140,
          height: 200,
          child: ListenableBuilder(
            listenable: session.controllerListenable,
            builder: (context, _) {
              final renderer = _pickRenderer();
              final placeholder = _placeholderInfo();
              final muted = switch (session) {
                OneToOneCallSession(:final controller) => controller.muted,
                GroupCallSession(:final controller) => controller.muted,
              };
              return Stack(
                fit: StackFit.expand,
                children: [
                  if (renderer != null)
                    RTCVideoView(
                      key: ObjectKey(renderer),
                      renderer,
                      objectFit:
                          RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
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
                  Positioned(
                    right: 4,
                    top: 4,
                    child: _MiniIconButton(
                      icon: Icons.call_end,
                      color: Colors.red,
                      onTap: () => ref
                          .read(activeCallSessionProvider.notifier)
                          .endCall(),
                    ),
                  ),
                  Positioned(
                    left: 4,
                    bottom: 4,
                    child: _MiniIconButton(
                      icon: muted ? Icons.mic_off : Icons.mic,
                      color: Colors.black54,
                      onTap: () {
                        switch (session) {
                          case OneToOneCallSession(:final controller):
                            controller.toggleMute();
                          case GroupCallSession(:final controller):
                            controller.toggleMute();
                        }
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
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
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 28,
          height: 28,
          child: Icon(icon, color: Colors.white, size: 16),
        ),
      ),
    );
  }
}
