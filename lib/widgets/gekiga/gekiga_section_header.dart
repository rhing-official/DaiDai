import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/app_ui_style.dart';
import '../../providers/app_ui_style_provider.dart';
import 'gekiga_label_chip.dart';

/// セクションの見出し。劇画スタイル時は黒地白文字の[GekigaLabelChip]、
/// フラットスタイル時は太字テキストにする（2026-08-05新規。元は
/// `settings_tab.dart`の`_SectionHeader`が個別に持っていたロジックだが、
/// `profile_tab.dart`の蔵・工房の見出し（アイコン・背景画像・呼び名・
/// 一言・SNSのURL・会話ごとのプロフィールカード）にも同じ見た目を適用する
/// ため共通化した）。paddingは呼び出し側の既存レイアウトに委ねるため
/// 持たない（`settings_tab.dart`側は独自にPaddingで包む）。
class GekigaSectionHeader extends ConsumerWidget {
  const GekigaSectionHeader(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isGekiga = ref.watch(appUiStyleProvider) == AppUiStyle.gekiga;
    return isGekiga
        ? Align(alignment: Alignment.centerLeft, child: GekigaLabelChip(title))
        : Text(title, style: const TextStyle(fontWeight: FontWeight.bold));
  }
}
