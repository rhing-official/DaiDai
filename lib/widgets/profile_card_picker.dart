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
    super.key,
  });

  final Strings strings;
  final List<ProfileCard> cards;

  /// nullは「標準」が選択されていることを表す。
  final String? selectedCardId;

  /// nullを渡すと「標準」が選ばれたことを表す。
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        ChoiceChip(
          label: Text(strings.profileCardPickerStandardOption),
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
