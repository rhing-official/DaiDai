import 'package:flutter/material.dart';

import '../../l10n/religious_holidays.dart';
import '../../l10n/strings.dart';
import '../../models/calendar_system.dart';
import '../../models/calendar_week_start.dart';
import '../../providers/holiday_settings_provider.dart';
import '../../theme/gekiga/gekiga_colors.dart';
import '../../widgets/gekiga/gekiga_panel_box.dart';
import '../../widgets/pressable_scale.dart';
import '../../widgets/toggles/app_checkbox.dart';

/// カレンダー設定の共通部品（2026-11-05）。設定>語らい>カレンダー（標準）と、
/// カレンダーの歯車ポップアップ（この語らいだけの設定）の両方で使う。色は呼び出し側が
/// 決める（[foreground]が文字色、[background]がその反対色。選択中は文字色で塗り、
/// 文字は背景色側にする。アクセントカラーは文字に使わない）。

/// 1行に並べる選択肢のチップ。[value]がnullの選択肢は「標準に合わせる」。
class CalendarChoiceRow<T> extends StatelessWidget {
  const CalendarChoiceRow({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
    required this.foreground,
    required this.background,
    this.gekigaBlocks = false,
  });

  /// trueなら劇画の黒いブロックの並びで描く。
  final bool gekigaBlocks;
  final List<({T? value, String label})> options;
  final T? selected;
  final ValueChanged<T?> onSelected;
  final Color foreground;
  final Color background;

  @override
  Widget build(BuildContext context) {
    if (gekigaBlocks) {
      return GekigaJointedTileList(
        axis: Axis.horizontal,
        seeds: [for (final o in options) o.label.hashCode],
        selectedFlags: [for (final o in options) o.value == selected],
        children: [
          for (final o in options)
            GekigaTileContent(
              selected: o.value == selected,
              title: Text(o.label),
              onTap: () => onSelected(o.value),
            ),
        ],
      );
    }
    return Row(
      children: [
        for (var i = 0; i < options.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: _Chip(
              text: options[i].label,
              selected: options[i].value == selected,
              onTap: () => onSelected(options[i].value),
              foreground: foreground,
              background: background,
            ),
          ),
        ],
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.text,
    required this.selected,
    required this.onTap,
    required this.foreground,
    required this.background,
  });

  final String text;
  final bool selected;
  final VoidCallback onTap;
  final Color foreground;
  final Color background;

  @override
  Widget build(BuildContext context) {
    // 選択の色・文字の太さはなめらかに切り替わり、押すと少し沈んで弾んで戻る。
    return GestureDetector(
      onTap: onTap,
      child: PressableScale(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? foreground : Colors.transparent,
            border: Border.all(color: foreground.withValues(alpha: 0.6)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: selected ? background : foreground,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            ),
            child: Text(text),
          ),
        ),
      ),
    );
  }
}

String calendarSystemLabelOf(Strings strings, CalendarSystem system) =>
    switch (system) {
      CalendarSystem.gregorian => strings.calendarSystemGregorian,
      CalendarSystem.japanese => strings.calendarSystemJapanese,
    };

/// 週の始まりの選択肢（日曜・月曜）。
List<({CalendarWeekStart? value, String label})> weekStartOptions(
  Strings strings, {
  bool withDefault = false,
  String? defaultLabel,
}) => [
  if (withDefault) (value: null, label: defaultLabel ?? ''),
  (value: CalendarWeekStart.sunday, label: strings.calendarWeekStartSunday),
  (value: CalendarWeekStart.monday, label: strings.calendarWeekStartMonday),
];

/// 暦の選択肢（西暦・和暦）。
List<({CalendarSystem? value, String label})> calendarSystemOptions(
  Strings strings, {
  bool withDefault = false,
  String? defaultLabel,
}) => [
  if (withDefault) (value: null, label: defaultLabel ?? ''),
  for (final system in CalendarSystem.values)
    (value: system, label: calendarSystemLabelOf(strings, system)),
];

/// 表示する祝日・祭日・宗教上の祝日のチェックボックス。Googleカレンダーと同じく、
/// 地域・祭日・宗教を分け、地域と宗教は複数選べる。
class HolidayCheckboxes extends StatelessWidget {
  const HolidayCheckboxes({
    super.key,
    required this.strings,
    required this.settings,
    required this.residenceCountry,
    required this.onRegion,
    required this.onObservances,
    required this.onReligion,
    required this.foreground,
    required this.background,
    this.gekigaBlocks = false,
  });

  /// trueなら劇画の黒いブロック（設定画面用）で描く。
  final bool gekigaBlocks;
  final Strings strings;
  final HolidaySettings settings;
  final String residenceCountry;
  final void Function(String country, bool enabled) onRegion;
  final ValueChanged<bool> onObservances;
  final void Function(String religion, bool enabled) onReligion;
  final Color foreground;
  final Color background;

  Widget _row(String label, bool value, ValueChanged<bool> onChanged) {
    if (gekigaBlocks) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: GekigaJointedTileList(
          seeds: [label.hashCode],
          selectedFlags: [value],
          children: [
            GekigaTileContent(
              selected: value,
              leading: AppCheckbox(
                value: value,
                onChanged: (v) => onChanged(v ?? false),
                // 選択中は白地・未選択は黒地のブロックなので、チェックの色を行に合わせる。
                foreground: value ? GekigaColors.panel : GekigaColors.onPanel,
                background: value ? GekigaColors.onPanel : GekigaColors.panel,
              ),
              title: Text(label),
              onTap: () => onChanged(!value),
            ),
          ],
        ),
      );
    }
    return InkWell(
      onTap: () => onChanged(!value),
      child: Row(
        children: [
          SizedBox(
            width: 32,
            height: 32,
            child: AppCheckbox(
              value: value,
              onChanged: (v) => onChanged(v ?? false),
              foreground: foreground,
              background: background,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(label, style: TextStyle(color: foreground)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final regions = settings.effectiveRegions(residenceCountry);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _row(
          strings.holidayRegionJapan,
          regions.contains('JP'),
          (v) => onRegion('JP', v),
        ),
        _row(
          strings.holidayObservancesLabel,
          settings.observances,
          onObservances,
        ),
        _row(
          strings.holidayReligionChristian,
          settings.religions.contains(kReligionChristian),
          (v) => onReligion(kReligionChristian, v),
        ),
        _row(
          strings.holidayReligionBuddhist,
          settings.religions.contains(kReligionBuddhist),
          (v) => onReligion(kReligionBuddhist, v),
        ),
      ],
    );
  }
}
