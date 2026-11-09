import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/message.dart';

/// 語らい一覧のブロックに出す「最終投稿メッセージ」（一対・広場の本体に非正規化して
/// 持つ`lastMessageAt`/`lastMessageSenderId`/`lastMessageContentType`/`lastMessagePreview`）
/// を、送信取り消しの後に直す為の補助（2026-11-09）。
///
/// 取り消したメッセージが最終メッセージだった時だけ、残っているメッセージのうち
/// 最も新しいものへ戻す。無ければ4項目を消す。
class LastMessageUpdate {
  LastMessageUpdate._();

  /// 取り消す[target]が、本体に記録された最終メッセージか。送信は同じバッチで
  /// 寄合と本体の`lastMessageAt`を`serverTimestamp()`で書くので、時刻が一致する。
  static bool isLast({
    required Message target,
    required Timestamp? conversationLastAt,
    required String? conversationLastSenderId,
  }) {
    final sentAt = target.sentAt;
    if (sentAt == null || conversationLastAt == null) return false;
    return sentAt == conversationLastAt &&
        target.senderId == conversationLastSenderId;
  }

  /// [latest]（残った中で最も新しいメッセージ。無ければnull）から、本体へ書く更新内容を作る。
  static Map<String, Object?> fieldsFor(Message? latest) {
    if (latest == null) {
      return {
        'lastMessageAt': FieldValue.delete(),
        'lastMessageSenderId': FieldValue.delete(),
        'lastMessageContentType': FieldValue.delete(),
        'lastMessagePreview': FieldValue.delete(),
      };
    }
    // プレビューの本文は、送信時と同じく`text`/`call`だけに入れる。
    final hasPreview =
        latest.contentType == 'text' || latest.contentType == 'call';
    return {
      'lastMessageAt': latest.sentAt,
      'lastMessageSenderId': latest.senderId,
      'lastMessageContentType': latest.contentType,
      'lastMessagePreview': hasPreview
          ? messageSnippetOf(latest.content)
          : null,
    };
  }

  /// 残っているメッセージのうち最も新しいもの（[candidates]の最大の`sentAt`）。
  static Message? newest(Iterable<Message> candidates) {
    Message? best;
    for (final m in candidates) {
      if (m.sentAt == null) continue;
      if (best == null || m.sentAt!.compareTo(best.sentAt!) > 0) best = m;
    }
    return best;
  }
}
