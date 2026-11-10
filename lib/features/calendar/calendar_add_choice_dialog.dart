import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';
import '../../widgets/two_choice_dialog.dart';

/// カレンダーの日付クリック時に「予定追加」か「日程調整」かを選ばせるダイアログ
/// （2026-09-05追加、`calendar_pane_view.dart`・`calendar_popup_content.dart`から呼ばれる）。
/// 語らいの「＋」（一対／広場）と同じ2択のポップアップ（`showTwoChoiceDialog`、
/// 2026-11-10に共通化。UIスタイルに沿った意匠・大きさ・区切り線）。
enum CalendarAddChoice { event, scheduleCoordination }

Future<CalendarAddChoice?> showCalendarAddChoiceDialog(
  BuildContext context,
) async {
  final strings = ProviderScope.containerOf(context).read(appStringsProvider);
  return showTwoChoiceDialog<CalendarAddChoice>(
    context: context,
    barrierLabel: strings.calendarAddChoiceDialogTitle,
    left: TwoChoiceOption(
      icon: Icons.event_outlined,
      title: strings.calendarAddChoiceEventOption,
      subtitle: strings.calendarAddChoiceEventSubtitle,
      onTap: (dialogContext) =>
          Navigator.of(dialogContext).pop(CalendarAddChoice.event),
    ),
    right: TwoChoiceOption(
      icon: Icons.event_available_outlined,
      title: strings.calendarAddChoiceCoordinationOption,
      subtitle: strings.calendarAddChoiceCoordinationSubtitle,
      onTap: (dialogContext) => Navigator.of(
        dialogContext,
      ).pop(CalendarAddChoice.scheduleCoordination),
    ),
  );
}
