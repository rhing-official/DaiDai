/// Googleカレンダー同期（2026-09-01追加）向けの日時変換ロジックを集約する。
///
/// Firestore上の[CalendarEvent]（`lib/models/calendar_event.dart`）は
/// `Timestamp`（内部的にはUTC瞬間）で日時を持つが、Google Calendar API
/// （`events.insert`/`events.update`）はRFC3339のローカル日時＋UTCオフセット
/// （時刻指定の予定）または`YYYY-MM-DD`（終日予定）という別の表現を要求する。
/// IANAタイムゾーン名（`Asia/Tokyo`等）は取得に専用パッケージが必要になり
/// 依存が増えるため使わず、RFC3339の明示的なUTCオフセット表記だけで表現する
/// （終日ではない予定については、`timeZone`フィールドを省略してもオフセット
/// 付きの`dateTime`だけでGoogle Calendar APIは正しく解釈できる）。
library;

/// [local]（端末のローカル時刻として扱う[DateTime]）をRFC3339のUTCオフセット
/// 付き文字列に変換する（例: `2026-09-01T10:00:00+09:00`）。
String toRfc3339WithOffset(DateTime local) {
  final offset = local.timeZoneOffset;
  final sign = offset.isNegative ? '-' : '+';
  final hours = offset.inHours.abs().toString().padLeft(2, '0');
  final minutes = (offset.inMinutes.abs() % 60).toString().padLeft(2, '0');
  final iso = local.toIso8601String();
  // toIso8601String()の末尾ミリ秒（".000"）はGoogle Calendar API側では
  // 不要なため取り除く。
  final withoutMillis = iso.contains('.') ? iso.split('.').first : iso;
  return '$withoutMillis$sign$hours:$minutes';
}

/// [local]の年月日部分だけを`YYYY-MM-DD`形式にする（終日予定用）。
String toDateOnly(DateTime local) {
  final year = local.year.toString().padLeft(4, '0');
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}

/// 終日予定のGoogle Calendar API向け終了日（排他的な翌日）を計算する。
/// [endLocal]が未指定（終了日未定）の場合は[startLocal]と同じ日を1日だけの
/// 予定として扱う。
DateTime exclusiveAllDayEnd(DateTime startLocal, DateTime? endLocal) {
  final base = endLocal ?? startLocal;
  final dateOnly = DateTime(base.year, base.month, base.day);
  return dateOnly.add(const Duration(days: 1));
}
