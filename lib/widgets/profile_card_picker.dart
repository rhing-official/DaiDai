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
    this.activeCard,
    super.key,
  });

  final Strings strings;
  final List<ProfileCard> cards;

  /// nullは「標準」が選択されていることを表す。
  final String? selectedCardId;

  /// nullを渡すと「標準」が選ばれたことを表す。
  final ValueChanged<String?> onSelected;

  /// 現在「標準」に設定されているカード（[AppUser.activeProfileCard]）。
  /// 指定すると、そのカードは「$name（標準）」の1行にまとめ、他のカードの
  /// 並びからは除く（2026-10-11変更。以前は「標準（新）」と「新」が別の行で
  /// 並び、同じ物が別物に見えた）。標準の行を選ぶ＝標準に追従（null）で、
  /// 標準と同じカードを個別に固定する選択肢は出さない。nullなら（標準が
  /// 未設定）「標準」の行＋全カード。
  final ProfileCard? activeCard;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isGekiga = ref.watch(appUiStyleProvider) == AppUiStyle.gekiga;
    final active = activeCard;
    final standardLabel = active != null
        ? strings.profileCardPickerStandardOptionWithName(active.name)
        : strings.profileCardPickerStandardOption;

    final options = <({String? id, String label})>[
      (id: null, label: standardLabel),
      for (final card in cards)
        if (card.id != active?.id) (id: card.id, label: card.name),
    ];
    // 標準と同じカードを固定していた過去の設定も、標準の行の選択として見せる。
    final effectiveSelectedId = selectedCardId == active?.id
        ? null
        : selectedCardId;

    if (isGekiga) {
      return GekigaJointedTileList(
        seeds: [for (final option in options) option.label.hashCode],
        selectedFlags: [
          for (final option in options) option.id == effectiveSelectedId,
        ],
        children: [
          for (final option in options)
            GekigaTileContent(
              selected: option.id == effectiveSelectedId,
              leading: Icon(
                option.id == effectiveSelectedId
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
      groupValue: effectiveSelectedId,
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
