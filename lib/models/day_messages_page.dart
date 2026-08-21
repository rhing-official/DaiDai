import 'message.dart';

/// [DirectMessageRepository.loadOlderDayMessages]/
/// [GroupRepository.loadOlderRoomDayMessages]が返す、1暦日分のメッセージ
/// ページ（2026-08-20追加、メッセージ読み込みの1日単位ページネーション）。
class DayMessagesPage {
  const DayMessagesPage({required this.dayStart, required this.messages});

  /// このページが属する暦日の開始時刻（ローカル時刻の00:00）。次の
  /// [DirectMessageRepository.loadOlderDayMessages]呼び出しの
  /// `beforeDayStart`にそのまま渡せる。
  final DateTime dayStart;

  final List<Message> messages;
}
