import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../l10n/strings.dart';
import '../../models/app_ui_style.dart';
import '../../providers/app_locale_provider.dart';
import '../../providers/app_ui_style_provider.dart';
import '../../widgets/glass/glass_dialog.dart';

/// 複数の日付をカレンダー上でトグル選択するダイアログ（2026-09-07追加、
/// 日程調整の候補日選択用）。`initialSelectedDates`を初期状態として開き、
/// 「完了」を押すと選択中の日付集合を返す。キャンセルされたら`null`。
Future<Set<DateTime>?> showMultiDatePickerDialog(
  BuildContext context, {
  required Set<DateTime> initialSelectedDates,
}) {
  return showDialog<Set<DateTime>>(
    context: context,
    builder: (_) =>
        _MultiDatePickerDialog(initialSelectedDates: initialSelectedDates),
  );
}

DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

class _MultiDatePickerDialog extends ConsumerStatefulWidget {
  const _MultiDatePickerDialog({required this.initialSelectedDates});

  final Set<DateTime> initialSelectedDates;

  @override
  ConsumerState<_MultiDatePickerDialog> createState() =>
      _MultiDatePickerDialogState();
}

class _MultiDatePickerDialogState
    extends ConsumerState<_MultiDatePickerDialog> {
  late final DateTime _firstDate = _dateOnly(
    DateTime.now().subtract(const Duration(days: 365 * 5)),
  );
  late final DateTime _lastDate = _dateOnly(
    DateTime.now().add(const Duration(days: 365 * 5)),
  );
  late final Set<DateTime> _selected = {...widget.initialSelectedDates};
  late DateTime _visibleMonth = _selected.isEmpty
      ? DateTime(DateTime.now().year, DateTime.now().month)
      : DateTime(_selected.first.year, _selected.first.month);

  void _toggle(DateTime day) {
    setState(() {
      if (!_selected.remove(day)) _selected.add(day);
    });
  }

  void _goToPreviousMonth() {
    setState(
      () =>
          _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month - 1),
    );
  }

  void _goToNextMonth() {
    setState(
      () =>
          _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month + 1),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final localeCode = ref.watch(appLocaleProvider).languageCode;
    final isGlass = ref.watch(appUiStyleProvider) == AppUiStyle.glass;
    final colorScheme = Theme.of(context).colorScheme;

    final title = Text(strings.scheduleCoordinationCandidatePickerTitle);
    final content = SizedBox(
      width: 320,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                tooltip: '',
                onPressed: _goToPreviousMonth,
              ),
              Expanded(
                child: Text(
                  DateFormat.yMMMM(localeCode).format(_visibleMonth),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                tooltip: '',
                onPressed: _goToNextMonth,
              ),
            ],
          ),
          _WeekdayHeaderRow(localeCode: localeCode),
          _SelectableMonthGrid(
            visibleMonth: _visibleMonth,
            selected: _selected,
            firstDate: _firstDate,
            lastDate: _lastDate,
            colorScheme: colorScheme,
            onToggle: _toggle,
          ),
        ],
      ),
    );
    final actions = [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(strings.cancel),
      ),
      FilledButton(
        onPressed: _selected.isEmpty
            ? null
            : () => Navigator.of(context).pop(_selected),
        child: Text(strings.done),
      ),
    ];

    return isGlass
        ? GlassAlertDialog(title: title, content: content, actions: actions)
        : AlertDialog(title: title, content: content, actions: actions);
  }
}

class _WeekdayHeaderRow extends StatelessWidget {
  const _WeekdayHeaderRow({required this.localeCode});

  final String localeCode;

  @override
  Widget build(BuildContext context) {
    // 2023-01-01は日曜日。この週の7日分から曜日ラベル（最短表記）を作る
    // （calendar_pane_view.dartの`_WeekdayHeaderRow`と同じ計算）。
    final anchor = DateTime(2023, 1, 1);
    final labelStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    return Row(
      children: [
        for (var i = 0; i < 7; i++)
          Expanded(
            child: Center(
              child: Text(
                DateFormat.EEEEE(
                  localeCode,
                ).format(anchor.add(Duration(days: i))),
                style: labelStyle,
              ),
            ),
          ),
      ],
    );
  }
}

class _SelectableMonthGrid extends StatelessWidget {
  const _SelectableMonthGrid({
    required this.visibleMonth,
    required this.selected,
    required this.firstDate,
    required this.lastDate,
    required this.colorScheme,
    required this.onToggle,
  });

  final DateTime visibleMonth;
  final Set<DateTime> selected;
  final DateTime firstDate;
  final DateTime lastDate;
  final ColorScheme colorScheme;
  final void Function(DateTime day) onToggle;

  @override
  Widget build(BuildContext context) {
    final year = visibleMonth.year;
    final month = visibleMonth.month;
    final firstOfMonth = DateTime(year, month);
    final daysInMonth = DateTime(year, month + 1, 0).day;
    // DateTime.weekday: 月=1...日=7。日曜始まりの先頭余白マス数に変換する
    // （calendar_pane_view.dartの`_MonthGrid`と同じ計算式）。
    final leadingBlanks = firstOfMonth.weekday % 7;
    final totalCells = leadingBlanks + daysInMonth;
    final trailingBlanks = (7 - totalCells % 7) % 7;

    final cells = <DateTime>[
      for (var i = leadingBlanks; i > 0; i--)
        firstOfMonth.subtract(Duration(days: i)),
      for (var d = 1; d <= daysInMonth; d++) DateTime(year, month, d),
      for (var i = 1; i <= trailingBlanks; i++)
        DateTime(year, month, daysInMonth).add(Duration(days: i)),
    ];

    final today = _dateOnly(DateTime.now());

    return GridView.count(
      crossAxisCount: 7,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        for (final day in cells)
          _SelectableDayCell(
            day: day,
            isSelected: selected.contains(day),
            isToday: day == today,
            isEnabled:
                day.month == month &&
                !day.isBefore(firstDate) &&
                !day.isAfter(lastDate),
            colorScheme: colorScheme,
            onTap: () => onToggle(day),
          ),
      ],
    );
  }
}

class _SelectableDayCell extends StatelessWidget {
  const _SelectableDayCell({
    required this.day,
    required this.isSelected,
    required this.isToday,
    required this.isEnabled,
    required this.colorScheme,
    required this.onTap,
  });

  final DateTime day;
  final bool isSelected;
  final bool isToday;
  final bool isEnabled;
  final ColorScheme colorScheme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dayNumberColor = !isEnabled
        ? colorScheme.onSurface.withValues(alpha: 0.25)
        : isSelected
        ? colorScheme.onPrimary
        : colorScheme.onSurface;

    return Padding(
      padding: const EdgeInsets.all(2),
      child: InkWell(
        onTap: isEnabled ? onTap : null,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          decoration: BoxDecoration(
            color: isSelected ? colorScheme.primary : null,
            border: (!isSelected && isToday)
                ? Border.all(color: colorScheme.outline, width: 2)
                : null,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Text('${day.day}', style: TextStyle(color: dayNumberColor)),
          ),
        ),
      ),
    );
  }
}
