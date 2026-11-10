import 'package:flutter/material.dart';

import 'multi_date_picker_dialog.dart';

/// 日付→時刻の順に選ぶ共通の処理（2026-11-10、送信予約で採用したカレンダーと時刻ピッカーを、
/// 予定・日程調整の回答期限・投票の期限にも流用した）。
///
/// 日付は週の始まりを語らいのカレンダーの設定に従う自前のカレンダー（`/`表記、
/// [firstDate]より前は選べない）、時刻は標準の時刻ピッカー（アプリ全体の
/// `dialogTheme.constraints`が効いて崩れないよう、この範囲だけ既定に戻す）。
/// [withTime]がfalseなら日付だけ返す（終日の予定）。[isValid]を渡すと、満たさない時刻では[onInvalid]を
/// 呼んで時刻ピッカーを開き直す。キャンセルなら`null`。
Future<DateTime?> pickDateAndTime(
  BuildContext context, {
  required String conversationId,
  required DateTime initial,
  required DateTime firstDate,
  required DateTime lastDate,
  String? title,
  bool withTime = true,
  bool Function(DateTime picked)? isValid,
  VoidCallback? onInvalid,
}) async {
  final date = await showSingleDatePickerDialog(
    context,
    initialDate: initial,
    firstDate: firstDate,
    lastDate: lastDate,
    conversationId: conversationId,
    title: title,
  );
  if (date == null || !context.mounted) return null;
  if (!withTime) return DateTime(date.year, date.month, date.day);
  final time = isValid == null
      ? await showTimePicker(
          context: context,
          initialTime: TimeOfDay.fromDateTime(initial),
          helpText: title,
          builder: _resetDialogConstraints,
        )
      : await _showValidatedTimePicker(
          context,
          initialTime: TimeOfDay.fromDateTime(initial),
          helpText: title,
          isValid: (t) => isValid(
            DateTime(date.year, date.month, date.day, t.hour, t.minute),
          ),
          onInvalid: onInvalid,
        );
  if (time == null) return null;
  return DateTime(date.year, date.month, date.day, time.hour, time.minute);
}

Widget _resetDialogConstraints(BuildContext context, Widget? child) {
  return Theme(
    data: Theme.of(context).copyWith(dialogTheme: const DialogThemeData()),
    child: child!,
  );
}

/// 「OK」を押した時に[isValid]を満たさなければ、[onInvalid]（バナーなど）を呼ぶだけで、
/// 時刻ピッカーを閉じない（モード・入力中の時刻も、そのまま）。標準の`showTimePicker`は
/// 「OK」で必ず閉じるので、`TimePickerDialog`を入れ子の`Navigator`に載せ、その`pop`を
/// 止めている。
Future<TimeOfDay?> _showValidatedTimePicker(
  BuildContext context, {
  required TimeOfDay initialTime,
  required bool Function(TimeOfDay time) isValid,
  String? helpText,
  VoidCallback? onInvalid,
}) {
  return showDialog<TimeOfDay>(
    context: context,
    builder: (outerContext) => Theme(
      data: Theme.of(
        outerContext,
      ).copyWith(dialogTheme: const DialogThemeData()),
      child: Navigator(
        pages: [
          MaterialPage<void>(
            key: const ValueKey('time-picker'),
            child: TimePickerDialog(
              initialTime: initialTime,
              helpText: helpText,
            ),
          ),
        ],
        // ignore: deprecated_member_use
        onPopPage: (route, result) {
          final time = result as TimeOfDay?;
          if (time != null && !isValid(time)) {
            onInvalid?.call();
            return false;
          }
          Navigator.of(outerContext).pop(time);
          return false;
        },
      ),
    ),
  );
}
