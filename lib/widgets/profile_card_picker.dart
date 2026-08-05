import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../models/profile_card.dart';

/// 会話（一対・広場）ごとに使うプロフィールカードを選ぶ軽量ピッカー。
/// 「標準」＋[cards]の各カード名を[ChoiceChip]で並べる。広場参加・
/// 友達申請3系統・全体設定（設定タブ＞語らい）の計5箇所で使い回す
/// （`AppUser.conversationProfileCardId`、2026-07-29追加）。
class ProfileCardPicker extends StatelessWidget {
  const ProfileCardPicker({
    required this.strings,
    required this.cards,
    required this.selectedCardId,
    required this.onSelected,
    this.activeCardName,
    super.key,
  });

  final Strings strings;
  final List<ProfileCard> cards;

  /// nullは「標準」が選択されていることを表す。
  final String? selectedCardId;

  /// nullを渡すと「標準」が選ばれたことを表す。
  final ValueChanged<String?> onSelected;

  /// 現在「標準」が指している実際のカード名（[AppUser.activeProfileCard]の
  /// `name`）。指定すると「標準」チップの表示を「標準（$activeCardName）」に
  /// する（2026-08-05追加）。「標準」チップと、たまたま同名のカードチップが
  /// 並んで見え、重複しているように見えるという指摘への対応。「標準」＝
  /// 今後デフォルトを変更すれば自動追従、名前付きカードを選ぶ＝そのカードに
  /// 固定、という意味の違い自体は変えていない。nullなら（アクティブなカード
  /// が無い等）元の表示のまま。
  final String? activeCardName;

  @override
  Widget build(BuildContext context) {
    final name = activeCardName;
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        ChoiceChip(
          label: Text(
            name != null
                ? strings.profileCardPickerStandardOptionWithName(name)
                : strings.profileCardPickerStandardOption,
          ),
          selected: selectedCardId == null,
          onSelected: (_) => onSelected(null),
        ),
        for (final card in cards)
          ChoiceChip(
            label: Text(card.name),
            selected: selectedCardId == card.id,
            onSelected: (_) => onSelected(card.id),
          ),
      ],
    );
  }
}
