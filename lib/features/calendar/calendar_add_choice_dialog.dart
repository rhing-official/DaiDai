import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';
import '../../models/app_ui_style.dart';
import '../../providers/app_ui_style_provider.dart';
import '../../widgets/glass/glass_dialog.dart';

/// カレンダーの日付クリック時に「予定追加」か「日程調整」かを選ばせる
/// ダイアログ（2026-09-05追加、`calendar_pane_view.dart`から呼ばれる）。
enum CalendarAddChoice { event, scheduleCoordination }

Future<CalendarAddChoice?> showCalendarAddChoiceDialog(
  BuildContext context,
) async {
  final container = ProviderScope.containerOf(context);
  final isGlass = container.read(appUiStyleProvider) == AppUiStyle.glass;
  final strings = container.read(appStringsProvider);
  return showDialog<CalendarAddChoice>(
    context: context,
    builder: (context) {
      final title = Text(strings.calendarAddChoiceDialogTitle);
      final actions = [
        TextButton(
          onPressed: () => Navigator.of(context).pop(CalendarAddChoice.event),
          child: Text(strings.calendarAddChoiceEventOption),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(context).pop(CalendarAddChoice.scheduleCoordination),
          child: Text(strings.calendarAddChoiceCoordinationOption),
        ),
      ];
      return isGlass
          ? GlassAlertDialog(
              title: title,
              content: const SizedBox.shrink(),
              actions: actions,
            )
          : AlertDialog(
              title: title,
              content: const SizedBox.shrink(),
              actions: actions,
            );
    },
  );
}
