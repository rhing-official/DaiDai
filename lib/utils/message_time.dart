import '../l10n/app_locale.dart';
import '../models/message_time_format.dart';

/// 曜日の略称（DateTime.weekdayの1=月曜〜7=日曜に対応）。日本語は1文字、
/// 英語は3文字略称で、どちらも略称表記に統一する。
const _weekdayAbbreviationsJa = ['月', '火', '水', '木', '金', '土', '日'];
const _weekdayAbbreviationsEn = [
  'Mon',
  'Tue',
  'Wed',
  'Thu',
  'Fri',
  'Sat',
  'Sun',
];

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
/// 常に絶対日付（yyyy/mm/dd）＋曜日の略称で表す。
String formatMessageDate(DateTime date, AppLocale locale) {
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  final abbreviations = locale == AppLocale.japanese
      ? _weekdayAbbreviationsJa
      : _weekdayAbbreviationsEn;
  final weekday = abbreviations[date.weekday - 1];
  return '${date.year}/$month/$day ($weekday)';
}

/// 2つの日時が同じ暦日（年・月・日）かどうか。メッセージ一覧で日付区切りを
/// 挿入する位置の判定に使う。
bool isSameDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}
