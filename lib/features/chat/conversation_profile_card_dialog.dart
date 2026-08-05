import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';
import '../../providers/repository_providers.dart';
import '../../providers/user_providers.dart';
import '../../widgets/profile_card_picker.dart';

/// 一対・広場ごとに自分が使うプロフィールカードを選ぶダイアログ
/// （`AppUser.conversationProfileCardId`、2026-07-30追加）。設定タブ＞語らい
/// の一覧（`_ProfileCardAssignmentFolder`）と同じ`ProfileCardPicker`を使い、
/// 各会話の全体設定（`GroupSettingsPopup`・単一モードの`_GroupMenuButton`・
/// `_DmMenuButton`）から直接開けるようにする。選択は即時保存（「完了」は
/// 閉じるだけ）で、権限ゲートは無い（自分がどのカードを使うかは個人設定）。
class ConversationProfileCardDialog extends ConsumerWidget {
  const ConversationProfileCardDialog({
    required this.currentUserId,
    required this.conversationId,
    super.key,
  });

  final String currentUserId;
  final String conversationId;

  static Future<void> show(
    BuildContext context, {
    required String currentUserId,
    required String conversationId,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => ConversationProfileCardDialog(
        currentUserId: currentUserId,
        conversationId: conversationId,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final liveUser = ref.watch(watchedUserProvider(currentUserId)).value;
    return AlertDialog(
      title: Text(strings.conversationProfileCardMenuLabel),
      content: liveUser == null
          ? const SizedBox(
              height: 48,
              child: Center(child: CircularProgressIndicator()),
            )
          : ProfileCardPicker(
              strings: strings,
              cards: liveUser.profileCards,
              selectedCardId:
                  liveUser.conversationProfileCardId[conversationId],
              activeCardName: liveUser.activeProfileCard?.name,
              onSelected: (id) => ref
                  .read(userRepositoryProvider)
                  .setConversationProfileCard(
                    userId: currentUserId,
                    conversationId: conversationId,
                    profileCardId: id,
                  ),
            ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.done),
        ),
      ],
    );
  }
}
