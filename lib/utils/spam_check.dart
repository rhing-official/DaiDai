import 'text_normalize.dart';

/// クライアント側スパムチェック（技術仕様書8.3レイヤー3）で送信を
/// 一時停止させた理由。
enum SpamCheckReason {
  /// `config/spamKeywords`のいずれかに本文が一致した。
  keyword,

  /// 同じ語らいで直近に同一内容を連続送信しようとした。
  repeatedContent,
}

class _SentEntry {
  _SentEntry(this.text, this.sentAt);
  final String text;
  final DateTime sentAt;
}

/// 語らいごとの直近送信履歴を保持し、同一内容の連続送信を検知する
/// （`ChatScreen`のStateに1つ持たせる想定、`sticker_suggestion_strip.dart`の
/// 会話ごとのデバウンス管理と同じ考え方、2026-09-07追加）。
class RecentSendHistory {
  final Map<String, List<_SentEntry>> _byConversation = {};

  static const _window = Duration(minutes: 2);
  static const _repeatThreshold = 3;

  /// [conversationId]へ本文[messageText]を送信したことを記録する。
  void record(String conversationId, String messageText) {
    final list = _byConversation.putIfAbsent(conversationId, () => []);
    list.add(_SentEntry(normalizeForMatch(messageText), DateTime.now()));
  }

  /// [conversationId]内で、直近[_window]以内に[messageText]と同じ内容を
  /// 既に[_repeatThreshold]回以上送っているか。
  bool isRepeated(String conversationId, String messageText) {
    final list = _byConversation[conversationId];
    if (list == null) return false;
    final normalized = normalizeForMatch(messageText);
    final cutoff = DateTime.now().subtract(_window);
    list.removeWhere((entry) => entry.sentAt.isBefore(cutoff));
    return list.where((entry) => entry.text == normalized).length >=
        _repeatThreshold;
  }
}

/// 技術仕様書8.3レイヤー3のクライアント側スパムチェック。[keywords]は
/// [SpamConfigRepository.watchSpamKeywords]で取得したスパムキーワード一覧、
/// [history]は同一語らい内での直近送信履歴。いずれかに該当すれば理由を
/// 返す（該当しなければnull）。判定はこの関数内で完結し、メッセージ本文が
/// サーバーへ送られることは無い（技術仕様書8.1「メッセージ内容はサーバー側で
/// 監視しない」方針を参照）。
SpamCheckReason? clientSideSpamCheck({
  required String messageText,
  required List<String> keywords,
  required String conversationId,
  required RecentSendHistory history,
}) {
  final normalized = normalizeForMatch(messageText);
  if (normalized.isEmpty) return null;

  final hasKeyword = keywords.any(
    (keyword) => normalized.contains(normalizeForMatch(keyword)),
  );
  if (hasKeyword) return SpamCheckReason.keyword;

  if (history.isRepeated(conversationId, messageText)) {
    return SpamCheckReason.repeatedContent;
  }
  return null;
}
