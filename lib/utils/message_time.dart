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
