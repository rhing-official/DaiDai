import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';
import '../../l10n/vocabulary.dart';
import '../../models/app_user.dart';
import '../../models/conversation_prefs.dart';
import '../../models/direct_message.dart';
import '../../models/dm_room.dart';
import '../../providers/block_providers.dart';
import '../../providers/conversation_prefs_providers.dart';
import '../../providers/direct_message_providers.dart';
import '../../providers/repository_providers.dart';
import '../../router/app_router.dart';
import '../../utils/auto_dismiss_banner.dart';
import '../../widgets/destructive_label.dart';
import '../../widgets/glass/glass_surface.dart';
import 'chat_panes.dart'
    show confirmDisableReadReceipts, confirmDisableRoomFeature;
import 'conversation_profile_card_dialog.dart';
import 'severance_dialog.dart';

/// [DmSettingsPopup]をガラスUI対応のダイアログでラップして開く
/// （`showGroupSettingsDialog`と同じ構成、2026-09-13追加）。
Future<void> showDmSettingsDialog(
  BuildContext context, {
  required AppUser currentUser,
  required DirectMessage dm,
  required String otherUserId,
  required bool isGlass,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) {
      final constrained = ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 640),
        child: DmSettingsPopup(
          currentUser: currentUser,
          dm: dm,
          otherUserId: otherUserId,
        ),
      );
      return isGlass
          ? Dialog(
              backgroundColor: Colors.transparent,
              elevation: 0,
              child: GlassSurface(
                variant: GlassVariant.floating,
                borderRadius: BorderRadius.circular(24),
                child: constrained,
              ),
            )
          : Dialog(child: constrained);
    },
  );
}

/// 一対（DM）全体の設定をまとめたポップアップ（2026-09-13追加）。
/// `GroupSettingsPopup`の一対版。以前は一対に専用の設定画面が無く、
/// ミュート・ブロック・既読設定・絶縁提案・寄合モード選択が全て
/// ハンバーガーメニュー（`chat_panes.dart`の`_DmMenuButton`）に一列で
/// 並んでいたのを、ここへ集約した。ハンバーガーメニューの「一対の設定」
/// 項目から常に開ける他、複数モード＋広い画面ではサイドバー（`RoomListPane`）
/// の歯車アイコンからも同じダイアログを開ける。
class DmSettingsPopup extends ConsumerWidget {
  const DmSettingsPopup({
    required this.currentUser,
    required this.dm,
    required this.otherUserId,
    super.key,
  });

  final AppUser currentUser;
  final DirectMessage dm;
  final String otherUserId;

  /// 寄合機能（複数寄合）のオン/オフを切り替える（2026-09-14変更、以前の
  /// 3択「単一／複数／寄合機能なし」を1つのトグルに簡略化した）。オフに
  /// する場合は事前に確認ダイアログを出す。オフへの変更は寄合が1つだけの
  /// 場合しか許可されない（`DirectMessageRepository.setRoomsEnabled`が
  /// 件数を検証し[StateError]を投げる）が、UI側も寄合が複数ある間は
  /// トグル自体を無効化するため、通常はここに到達する前に弾かれる
  /// （購読中の件数と実際の書き込み時点の件数がずれる競合状態のみ
  /// フォールバックとしてここで捕捉する）。
  Future<void> _toggleRoomsEnabled(
    BuildContext context,
    WidgetRef ref,
    Strings strings,
    Vocabulary vocab,
    bool enabled,
  ) async {
    if (!enabled) {
      final confirmed = await confirmDisableRoomFeature(
        context,
        strings,
        vocab,
      );
      if (!confirmed) return;
    }
    try {
      await ref
          .read(directMessageRepositoryProvider)
          .setRoomsEnabled(
            dm.dmId,
            enabled: enabled,
            requestedBy: currentUser.userId,
          );
    } on StateError catch (e) {
      if (context.mounted) showAutoDismissBanner(context, message: '$e');
    }
  }

  Future<bool> _confirmDeleteConversation(
    BuildContext context,
    Strings strings,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings.chatAccountDeletedConfirmTitle),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(strings.chatAccountDeletedConfirmButton),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final vocabulary = ref.watch(vocabularyProvider);
    final userId = currentUser.userId;
    // ポップアップを開いたまま切り替えても見た目がすぐ反映されるよう、
    // 呼び出し元から渡された一度きりのスナップショットではなく、ここで
    // 直接プロバイダをwatchする（2026-09-14修正。以前はコンストラクタ引数
    // `isBlocked`を使っていたが、`showDmSettingsDialog`の`showDialog`
    // builderが呼ばれた時点の値に固定され、トグル操作でFirestoreへの
    // 書き込み自体は成功してもダイアログの表示だけ更新されなかった）。
    final isBlocked =
        ref
            .watch(blockedUserIdsProvider(userId))
            .value
            ?.contains(otherUserId) ??
        false;
    // `dm`自体も同じ理由で陳腐化する（寄合機能トグルの見た目が更新
    // されない不具合、2026-09-14修正）。`GroupSettingsPopup`と同じ
    // `watchedDmProvider`を新設して直接watchする。
    final liveDm = ref.watch(watchedDmProvider(dm.dmId)).value ?? dm;
    final prefs =
        ref.watch(conversationPrefsProvider(userId)).value ??
        const <String, ConversationPrefs>{};
    final muted = prefs[liveDm.dmId]?.notificationsMuted ?? false;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 4, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  strings.dmSettingsTooltip,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            children: [
              if (currentUser.profileCards.length > 1)
                ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: Text(strings.conversationProfileCardMenuLabel),
                  onTap: () => ConversationProfileCardDialog.show(
                    context,
                    currentUserId: userId,
                    conversationId: liveDm.dmId,
                  ),
                ),
              const Divider(),
              StreamBuilder<List<DmRoom>>(
                stream: ref
                    .read(directMessageRepositoryProvider)
                    .watchRooms(dmId: liveDm.dmId, userId: userId),
                builder: (context, snapshot) {
                  final rooms = snapshot.data ?? const <DmRoom>[];
                  final locked = liveDm.roomsEnabled && rooms.length > 1;
                  return SwitchListTile(
                    value: liveDm.roomsEnabled,
                    title: Text(strings.dmMenuEnableMultipleRooms),
                    subtitle: locked
                        ? Text(strings.roomModeToggleLockedHint)
                        : null,
                    onChanged: locked
                        ? null
                        : (value) => _toggleRoomsEnabled(
                            context,
                            ref,
                            strings,
                            vocabulary,
                            value,
                          ),
                  );
                },
              ),
              const Divider(),
              SwitchListTile(
                value: muted,
                title: Text(
                  muted ? strings.conversationUnmute : strings.conversationMute,
                ),
                onChanged: (value) => ref
                    .read(conversationPrefsRepositoryProvider)
                    .setNotificationsMuted(
                      userId: userId,
                      conversationId: liveDm.dmId,
                      muted: value,
                    ),
              ),
              SwitchListTile(
                value: isBlocked,
                title: Text(
                  isBlocked
                      ? strings.conversationUnblock
                      : strings.conversationBlock,
                ),
                onChanged: (value) {
                  final repository = ref.read(blockRepositoryProvider);
                  if (value) {
                    repository.block(userId: userId, targetUserId: otherUserId);
                  } else {
                    repository.unblock(
                      userId: userId,
                      targetUserId: otherUserId,
                    );
                  }
                },
              ),
              ListTile(
                title: Text(
                  liveDm.readReceiptsEnabled
                      ? strings.conversationReadReceiptsProposeDisable
                      : strings.conversationReadReceiptsProposeEnable,
                ),
                enabled: liveDm.readReceiptsProposalBy == null,
                onTap: () async {
                  // 既読オン/オフは一対共有の1つの設定で、どちら向きの変更も
                  // 相手の承認が必要（提案は常に現在値の反転を意味する）。
                  // オフにする提案の場合のみ、提案前に警告を出す。
                  if (liveDm.readReceiptsEnabled) {
                    final confirmed = await confirmDisableReadReceipts(
                      context,
                      strings,
                    );
                    if (!confirmed) return;
                  }
                  ref
                      .read(directMessageRepositoryProvider)
                      .proposeReadReceiptsToggle(
                        dmId: liveDm.dmId,
                        userId: userId,
                      );
                },
              ),
              ListTile(
                title: Text(strings.conversationProposeSeverance),
                enabled: liveDm.severanceRequestedBy == null,
                onTap: () => SeveranceDialog.show(
                  context,
                  mode: SeveranceDialogMode.propose,
                  dmId: liveDm.dmId,
                  currentUserId: userId,
                  otherUserId: otherUserId,
                ),
              ),
              if (liveDm.accountDeletedUserId != null) ...[
                const Divider(),
                ListTile(
                  leading: Icon(
                    Icons.delete_forever,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  title: DestructiveLabel(
                    strings.dmMenuDeleteConversation(vocabulary.dm),
                  ),
                  onTap: () async {
                    final confirmed = await _confirmDeleteConversation(
                      context,
                      strings,
                    );
                    if (!confirmed) return;
                    await ref
                        .read(directMessageRepositoryProvider)
                        .deleteDmAfterAccountDeletion(
                          liveDm.dmId,
                          userId: userId,
                        );
                    if (context.mounted) {
                      Navigator.of(context).pop();
                      ref.read(goRouterProvider).go('/');
                    }
                  },
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
