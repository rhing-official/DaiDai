import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../l10n/strings.dart';
import '../../models/app_ui_style.dart';
import '../../providers/app_locale_provider.dart';
import '../../providers/app_ui_style_provider.dart';
import '../../models/calendar_week_start.dart';
import '../../providers/calendar_system_provider.dart';
import '../../widgets/glass/glass_dialog.dart';
import '../../widgets/dialog_keyboard_shortcuts.dart';
import '../../widgets/app_dialog.dart';

/// 複数の日付をカレンダー上でトグル選択するダイアログ（2026-09-07追加、
/// 日程調整の候補日選択用）。`initialSelectedDates`を初期状態として開き、
/// 「完了」を押すと選択中の日付集合を返す。キャンセルされたら`null`。
Future<Set<DateTime>?> showMultiDatePickerDialog(
  BuildContext context, {
  required Set<DateTime> initialSelectedDates,
  required String conversationId,
}) {
  return showAppDialog<Set<DateTime>>(
    context: context,
    builder: (_) => _MultiDatePickerDialog(
      initialSelectedDates: initialSelectedDates,
      conversationId: conversationId,
    ),
  );
}

/// 日付を1つ選ぶダイアログ（2026-11-10追加、送信予約の日付用）。週の始まりはその語らいの
/// カレンダーの設定に従い、月は「2026/11」、選択中の日付は「11/10(火)」と、`/`で表記する。
/// [firstDate]より前（過去）は選べず、前の月へも戻れない。キャンセルなら`null`。
Future<DateTime?> showSingleDatePickerDialog(
  BuildContext context, {
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
  required String conversationId,
  String? title,
}) {
  return showAppDialog<DateTime>(
    context: context,
    builder: (_) => _SingleDatePickerDialog(
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
      conversationId: conversationId,
      title: title,
    ),
  );
}

class _SingleDatePickerDialog extends ConsumerStatefulWidget {
  const _SingleDatePickerDialog({
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
    required this.conversationId,
    this.title,
  });

  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;
  final String conversationId;
  final String? title;

  @override
  ConsumerState<_SingleDatePickerDialog> createState() =>
      _SingleDatePickerDialogState();
}

class _SingleDatePickerDialogState
    extends ConsumerState<_SingleDatePickerDialog> {
  late DateTime _picked = _dateOnly(widget.initialDate);
  late DateTime _visibleMonth = DateTime(
    widget.initialDate.year,
    widget.initialDate.month,
  );

  bool get _canGoPrevious => DateTime(
    _visibleMonth.year,
    _visibleMonth.month - 1,
  ).isAfter(DateTime(widget.firstDate.year, widget.firstDate.month - 1));

  bool get _canGoNext => DateTime(
    _visibleMonth.year,
    _visibleMonth.month + 1,
  ).isBefore(DateTime(widget.lastDate.year, widget.lastDate.month + 1));

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final localeCode = ref.watch(appLocaleProvider).languageCode;
    final isGlass = ref.watch(appUiStyleProvider) == AppUiStyle.glass;
    final colorScheme = Theme.of(context).colorScheme;
    final weekStart = ref.watch(
      effectiveWeekStartProvider(widget.conversationId),
    );
    final monthLabel =
        '${_visibleMonth.year}/${_visibleMonth.month.toString().padLeft(2, '0')}';
    final pickedLabel =
        '${_picked.month}/${_picked.day}(${DateFormat.E(localeCode).format(_picked)})';

    final content = SizedBox(
      width: 400,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                pickedLabel,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
          ),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                tooltip: '',
                onPressed: _canGoPrevious
                    ? () => setState(
                        () => _visibleMonth = DateTime(
                          _visibleMonth.year,
                          _visibleMonth.month - 1,
                        ),
                      )
                    : null,
              ),
              Expanded(
                child: Text(
                  monthLabel,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                tooltip: '',
                onPressed: _canGoNext
                    ? () => setState(
                        () => _visibleMonth = DateTime(
                          _visibleMonth.year,
                          _visibleMonth.month + 1,
                        ),
                      )
                    : null,
              ),
            ],
          ),
          _WeekdayHeaderRow(localeCode: localeCode, weekStart: weekStart),
          _SelectableMonthGrid(
            weekStart: weekStart,
            visibleMonth: _visibleMonth,
            selected: {_picked},
            firstDate: _dateOnly(widget.firstDate),
            lastDate: _dateOnly(widget.lastDate),
            colorScheme: colorScheme,
            onToggle: (day) => setState(() => _picked = day),
          ),
        ],
      ),
    );
    final title = widget.title == null ? null : Text(widget.title!);
    final actions = [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(strings.cancel),
      ),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(_picked),
        child: Text(strings.done),
      ),
    ];
    return isGlass
        ? GlassAlertDialog(
            title: title,
            content: content,
            actions: actions,
            constraints: const BoxConstraints(maxWidth: 460),
          )
        : KeyboardAlertDialog(
            title: title,
            content: content,
            actions: actions,
            constraints: const BoxConstraints(maxWidth: 460),
          );
  }
}

DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

class _MultiDatePickerDialog extends ConsumerStatefulWidget {
  const _MultiDatePickerDialog({
    required this.initialSelectedDates,
    required this.conversationId,
  });

  final Set<DateTime> initialSelectedDates;

  /// 週の始まりを、この語らいのカレンダーの設定に合わせる為に使う。
  final String conversationId;

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
    final weekStart = ref.watch(
      effectiveWeekStartProvider(widget.conversationId),
    );

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
          _WeekdayHeaderRow(localeCode: localeCode, weekStart: weekStart),
          _SelectableMonthGrid(
            weekStart: weekStart,
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
        : KeyboardAlertDialog(title: title, content: content, actions: actions);
  }
}

class _WeekdayHeaderRow extends ConsumerWidget {
  const _WeekdayHeaderRow({required this.localeCode, required this.weekStart});

  final String localeCode;
  final CalendarWeekStart weekStart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 週の先頭の曜日（日曜/月曜、設定）から7日分の曜日ラベル（最短表記）を
    // 作る（calendar_pane_view.dartの`_WeekdayHeaderRow`と同じ計算）。
    final anchor = weekStart.weekdayLabelAnchor;
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

class _SelectableMonthGrid extends ConsumerWidget {
  const _SelectableMonthGrid({
    required this.weekStart,
    required this.visibleMonth,
    required this.selected,
    required this.firstDate,
    required this.lastDate,
    required this.colorScheme,
    required this.onToggle,
  });

  final CalendarWeekStart weekStart;
  final DateTime visibleMonth;
  final Set<DateTime> selected;
  final DateTime firstDate;
  final DateTime lastDate;
  final ColorScheme colorScheme;
  final void Function(DateTime day) onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final year = visibleMonth.year;
    final month = visibleMonth.month;
    final firstOfMonth = DateTime(year, month);
    final daysInMonth = DateTime(year, month + 1, 0).day;
    // 週の始まり（日曜/月曜、設定）に応じた先頭余白マス数
    // （calendar_pane_view.dartの`_MonthGrid`と同じ）。
    final leadingBlanks = weekStart.leadingBlanks(firstOfMonth);
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
