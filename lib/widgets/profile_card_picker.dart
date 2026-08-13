import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/strings.dart';
import '../models/app_ui_style.dart';
import '../models/profile_card.dart';
import '../providers/app_ui_style_provider.dart';
import 'gekiga/gekiga_panel_box.dart';

/// 会話（一対・広場）ごとに使うプロフィールカードを選ぶ単一選択ピッカー。
/// 「標準」＋[cards]の各カード名を並べる。広場参加・友達申請3系統・
/// 全体設定（設定タブ＞語らい）の計5箇所で使い回す
/// （`AppUser.conversationProfileCardId`、2026-07-29追加）。
/// 見た目はアプリの他の単一選択UI（`settings_tab.dart`の
/// `RadioGroup`+`RadioListTile`、劇画UI時は`GekigaJointedTileList`+
/// `GekigaTileContent`）に揃える（2026-08-14、以前は`ChoiceChip`＋`Wrap`
/// だったが見た目が浮いていたため変更）。
class ProfileCardPicker extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final isGekiga = ref.watch(appUiStyleProvider) == AppUiStyle.gekiga;
    final name = activeCardName;
    final standardLabel = name != null
        ? strings.profileCardPickerStandardOptionWithName(name)
        : strings.profileCardPickerStandardOption;

    final options = <({String? id, String label})>[
      (id: null, label: standardLabel),
      for (final card in cards) (id: card.id, label: card.name),
    ];

    if (isGekiga) {
      return GekigaJointedTileList(
        seeds: [for (final option in options) option.label.hashCode],
        selectedFlags: [
          for (final option in options) option.id == selectedCardId,
        ],
        children: [
          for (final option in options)
            GekigaTileContent(
              selected: option.id == selectedCardId,
              leading: Icon(
                option.id == selectedCardId
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
              ),
              title: Text(option.label),
              onTap: () => onSelected(option.id),
            ),
        ],
      );
    }

    return RadioGroup<String?>(
      groupValue: selectedCardId,
      onChanged: onSelected,
      child: Column(
        children: [
          for (final option in options)
            RadioListTile<String?>(value: option.id, title: Text(option.label)),
        ],
      ),
    );
  }
}
