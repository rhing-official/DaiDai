import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';
import '../../models/app_ui_style.dart';
import '../../models/app_user.dart';
import '../../models/poll.dart';
import '../../providers/app_ui_style_provider.dart';
import '../../providers/repository_providers.dart';
import '../../theme/popup_surface_colors.dart';
import '../../widgets/glass/glass_surface.dart';
import 'poll_form_dialog.dart';

/// 投票ボタンの真下に投票一覧をポップアップ表示する（2026-09-06追加、
/// `album_popup_content.dart`の`showAlbumPopup`と同じ構成）。位置計算済みの
/// [position]の元で`showMenu`を開き、選ばれた投票を返す（呼び出し元がそれを
/// 使って`showPollDetailDialog`を開く）。ヘッダーの「＋」からは
/// `showPollFormDialog`をこのポップアップの上に重ねて開く（アルバムの
/// `_createAlbum`と同じ設計。ポップアップ自体は閉じず、作成後は
/// `watchPolls`のストリームがそのまま一覧に反映する）。改名・削除は
/// アルバムと異なりここでは扱わない（削除は`PollDetailDialog`側の
/// 作成者専用アクションで行う）。
Future<Poll?> showPollPopup(
  BuildContext context, {
  required RelativeRect position,
  required bool isDm,
  required String conversationId,
  required String roomId,
  required AppUser currentUser,
}) {
  return showMenu<Poll>(
    context: context,
    position: position,
    color: Colors.transparent,
    shadowColor: Colors.transparent,
    elevation: 0,
    items: [
      PopupMenuItem<Poll>(
        enabled: false,
        padding: EdgeInsets.zero,
        child: _PollPopupContent(
          isDm: isDm,
          conversationId: conversationId,
          roomId: roomId,
          currentUser: currentUser,
        ),
      ),
    ],
  );
}

class _PollPopupContent extends ConsumerWidget {
  const _PollPopupContent({
    required this.isDm,
    required this.conversationId,
    required this.roomId,
    required this.currentUser,
  });

  final bool isDm;
  final String conversationId;
  final String roomId;
  final AppUser currentUser;

  Future<void> _createPoll(BuildContext context) {
    return showPollFormDialog(
      context,
      isDm: isDm,
      conversationId: conversationId,
      roomId: roomId,
      currentUserId: currentUser.userId,
      currentUserRhingId: currentUser.rhingId,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final brightness = Theme.of(context).brightness;
    final uiStyle = ref.watch(appUiStyleProvider);
    final onInverse = popupCardForeground(brightness, uiStyle);

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.poll_outlined, size: 16, color: onInverse),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                strings.pollListTitle,
                style: TextStyle(color: onInverse, fontWeight: FontWeight.bold),
              ),
            ),
            IconButton(
              icon: Icon(Icons.add, size: 20, color: onInverse),
              tooltip: '',
              onPressed: () => _createPoll(context),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
        const SizedBox(height: 8),
        StreamBuilder<List<Poll>>(
          stream: ref
              .read(pollRepositoryProvider)
              .watchPolls(
                isDm: isDm,
                conversationId: conversationId,
                roomId: roomId,
              ),
          builder: (context, snapshot) {
            final polls = snapshot.data ?? const <Poll>[];
            if (polls.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  strings.pollListEmptyMessage,
                  style: TextStyle(color: onInverse),
                ),
              );
            }
            final sorted = [...polls]
              ..sort(
                (a, b) => (b.createdAt?.millisecondsSinceEpoch ?? 0).compareTo(
                  a.createdAt?.millisecondsSinceEpoch ?? 0,
                ),
              );
            return ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final poll in sorted)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _PollPopupCard(
                          poll: poll,
                          uiStyle: uiStyle,
                          strings: strings,
                          onTap: () => Navigator.of(context).pop(poll),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );

    final padded = Padding(padding: const EdgeInsets.all(12), child: content);

    return SizedBox(
      width: 300,
      child: Container(
        decoration: BoxDecoration(
          color: popupCardBackground(brightness, uiStyle),
          border: Border.all(color: popupCardBorder(brightness, uiStyle)),
          borderRadius: BorderRadius.circular(16),
        ),
        child: padded,
      ),
    );
  }
}

/// ポップアップ内の投票1件分のカード。`_AlbumPopupCard`と同じ見た目の構成
/// （カード本体タップで選択）だが、投票には改名・削除のインライン操作が
/// 無いため右上の操作メニューは持たない。
class _PollPopupCard extends StatelessWidget {
  const _PollPopupCard({
    required this.poll,
    required this.uiStyle,
    required this.strings,
    required this.onTap,
  });

  final Poll poll;
  final AppUiStyle uiStyle;
  final Strings strings;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isGlass = uiStyle == AppUiStyle.glass;
    final brightness = Theme.of(context).brightness;
    final onInverse = popupCardForeground(brightness, uiStyle);

    final body = Padding(
      padding: const EdgeInsets.all(10),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: onInverse.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(Icons.poll_outlined, color: onInverse),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  poll.question,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: onInverse,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  poll.isClosed
                      ? strings.pollClosedBadgeLabel
                      : strings.pollResponseCountLabel(poll.responseCount),
                  style: TextStyle(
                    color: onInverse.withValues(alpha: 0.7),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return isGlass
        ? GlassSurface(
            variant: GlassVariant.card,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onTap,
              child: body,
            ),
          )
        : Material(
            color: onInverse.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onTap,
              child: body,
            ),
          );
  }
}
