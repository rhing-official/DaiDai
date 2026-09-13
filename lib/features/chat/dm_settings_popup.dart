import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';
import '../../l10n/vocabulary.dart';
import '../../models/app_user.dart';
import '../../models/conversation_prefs.dart';
import '../../models/direct_message.dart';
import '../../providers/conversation_prefs_providers.dart';
import '../../providers/repository_providers.dart';
import '../../router/app_router.dart';
import '../../widgets/destructive_label.dart';
import '../../widgets/glass/glass_surface.dart';
import 'chat_panes.dart'
    show confirmDisableReadReceipts, confirmDisableRoomFeature;
import 'conversation_profile_card_dialog.dart';
import 'severance_dialog.dart';

/// 一対（DM）の寄合モード（`DmSettingsPopup`/`GroupSettingsPopup`共通の
/// 考え方、2026-09-13追加）。`roomsEnabled`（単一→複数、一方向のみ）と
/// `roomFeatureDisabled`（単一モードの間だけ双方向に切り替え可能）という
/// 独立した2フィールドの組み合わせを、UI上は3択の1つの選択式コントロールに
/// 見せるための列挙。一対と広場で許可される遷移が異なる（一対は複数から
/// 戻せない）ため、共通ウィジェット化はせずそれぞれのファイルに同じ形の
/// 列挙を用意する。
enum _RoomMode { single, multiple, disabled }

_RoomMode _dmRoomMode(DirectMessage dm) {
  if (dm.roomsEnabled) return _RoomMode.multiple;
  if (dm.roomFeatureDisabled) return _RoomMode.disabled;
  return _RoomMode.single;
}

/// [DmSettingsPopup]をガラスUI対応のダイアログでラップして開く
/// （`showGroupSettingsDialog`と同じ構成、2026-09-13追加）。
Future<void> showDmSettingsDialog(
  BuildContext context, {
  required AppUser currentUser,
  required DirectMessage dm,
  required String otherUserId,
  required bool isBlocked,
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
          isBlocked: isBlocked,
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
    required this.isBlocked,
    super.key,
  });

  final AppUser currentUser;
  final DirectMessage dm;
  final String otherUserId;
  final bool isBlocked;

  Future<void> _selectRoomMode(
    BuildContext context,
    WidgetRef ref,
    Strings strings,
    Vocabulary vocab,
    _RoomMode target,
  ) async {
    final current = _dmRoomMode(dm);
    if (target == current) return;
    final repository = ref.read(directMessageRepositoryProvider);
    switch (target) {
      case _RoomMode.single:
        await repository.setRoomFeatureDisabled(dm.dmId, disabled: false);
      case _RoomMode.multiple:
        // 「機能なし」から選んだ場合は先に単一モードへ戻してから複数化する
        // （以前は一度「単一」に戻す手順が別途必要だったのを1手順に簡略化、
        // 2026-09-13）。
        if (current == _RoomMode.disabled) {
          await repository.setRoomFeatureDisabled(dm.dmId, disabled: false);
        }
        await repository.setRoomsEnabled(dm.dmId);
      case _RoomMode.disabled:
        final confirmed = await confirmDisableRoomFeature(
          context,
          strings,
          vocab,
        );
        if (!confirmed) return;
        await repository.setRoomFeatureDisabled(dm.dmId, disabled: true);
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
    final prefs =
        ref.watch(conversationPrefsProvider(userId)).value ??
        const <String, ConversationPrefs>{};
    final muted = prefs[dm.dmId]?.notificationsMuted ?? false;
    final roomMode = _dmRoomMode(dm);

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
                    conversationId: dm.dmId,
                  ),
                ),
              const Divider(),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Text(
                  strings.roomModeSectionTitle,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              RadioGroup<_RoomMode>(
                groupValue: roomMode,
                onChanged: (value) {
                  if (value != null) {
                    _selectRoomMode(context, ref, strings, vocabulary, value);
                  }
                },
                child: Column(
                  children: [
                    RadioListTile<_RoomMode>(
                      value: _RoomMode.single,
                      enabled: roomMode != _RoomMode.multiple,
                      title: Text(strings.roomModeSingleLabel),
                      subtitle: roomMode == _RoomMode.multiple
                          ? Text(strings.roomModeSingleLockedHint)
                          : null,
                    ),
                    RadioListTile<_RoomMode>(
                      value: _RoomMode.multiple,
                      enabled: roomMode != _RoomMode.multiple,
                      title: Text(strings.dmMenuEnableMultipleRooms),
                      subtitle: roomMode == _RoomMode.multiple
                          ? null
                          : Text(strings.roomModeMultipleIrreversibleHint),
                    ),
                    RadioListTile<_RoomMode>(
                      value: _RoomMode.disabled,
                      enabled: roomMode != _RoomMode.multiple,
                      title: Text(strings.roomModeDisabledLabel),
                      subtitle: roomMode == _RoomMode.multiple
                          ? Text(strings.roomModeSingleLockedHint)
                          : Text(strings.roomFeatureDisableConfirmMessage),
                    ),
                  ],
                ),
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
                      conversationId: dm.dmId,
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
                  dm.readReceiptsEnabled
                      ? strings.conversationReadReceiptsProposeDisable
                      : strings.conversationReadReceiptsProposeEnable,
                ),
                enabled: dm.readReceiptsProposalBy == null,
                onTap: () async {
                  // 既読オン/オフは一対共有の1つの設定で、どちら向きの変更も
                  // 相手の承認が必要（提案は常に現在値の反転を意味する）。
                  // オフにする提案の場合のみ、提案前に警告を出す。
                  if (dm.readReceiptsEnabled) {
                    final confirmed = await confirmDisableReadReceipts(
                      context,
                      strings,
                    );
                    if (!confirmed) return;
                  }
                  ref
                      .read(directMessageRepositoryProvider)
                      .proposeReadReceiptsToggle(dmId: dm.dmId, userId: userId);
                },
              ),
              ListTile(
                title: Text(strings.conversationProposeSeverance),
                enabled: dm.severanceRequestedBy == null,
                onTap: () => SeveranceDialog.show(
                  context,
                  mode: SeveranceDialogMode.propose,
                  dmId: dm.dmId,
                  currentUserId: userId,
                  otherUserId: otherUserId,
                ),
              ),
              if (dm.accountDeletedUserId != null) ...[
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
                        .deleteDmAfterAccountDeletion(dm.dmId, userId: userId);
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
