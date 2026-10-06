import 'package:cloud_firestore/cloud_firestore.dart';

/// 1回に読み込むメッセージ件数（ライブ窓・過去ページ共通、2026-10-06追加）。
/// 日単位の読み込みは1日の件数が極端にばらつき（少ない日が続くと読み込みが
/// 連鎖し、多い日は一度に重い）、件数ベースへ切り替えた。Discordと同規模。
const kMessagePageSize = 50;

/// 過去ページ読み込みの起点（これより古いメッセージを取得する）。
/// `sentAt`単独だと同時刻のメッセージが欠落しうるため、メッセージIDと
/// 組にして`(sentAt, messageId)`の降順カーソルとして使う
/// （`DirectMessageRepository.loadOlderMessages`/
/// `GroupRepository.loadOlderRoomMessages`）。
class MessageCursor {
  const MessageCursor({required this.sentAt, required this.messageId});

  final Timestamp sentAt;
  final String messageId;

  @override
  bool operator ==(Object other) =>
      other is MessageCursor &&
      other.sentAt == sentAt &&
      other.messageId == messageId;

  @override
  int get hashCode => Object.hash(sentAt, messageId);
}
