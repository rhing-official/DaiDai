import '../models/message_time_format.dart';

/// メッセージの送信時刻を、設定された表示形式で整形する。
/// 24時間表記は「00:00」、12時間表記は「12:00 p.m.」の形式。
String formatMessageTime(DateTime time, MessageTimeFormat format) {
  final minute = time.minute.toString().padLeft(2, '0');
  if (format == MessageTimeFormat.h24) {
    final hour = time.hour.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
  final isPm = time.hour >= 12;
  final hour12 = time.hour % 12 == 0 ? 12 : time.hour % 12;
  final suffix = isPm ? 'p.m.' : 'a.m.';
  return '$hour12:$minute $suffix';
}

/// メッセージ一覧の日付区切りに使う表示形式。相対表記（今日/昨日等）は使わず、
/// 常に絶対日付（yyyy/mm/dd）で表す。
String formatMessageDate(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}/$month/$day';
}

/// 2つの日時が同じ暦日（年・月・日）かどうか。メッセージ一覧で日付区切りを
/// 挿入する位置の判定に使う。
bool isSameDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}
