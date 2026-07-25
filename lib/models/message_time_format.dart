/// メッセージの送信時刻の表示形式。
enum MessageTimeFormat {
  /// 24時間表記（例: 00:00）。
  h24,

  /// 12時間表記＋午前/午後（例: 12:00 p.m.）。
  h12;

  static MessageTimeFormat fromName(String? name) {
    return MessageTimeFormat.values.firstWhere(
      (format) => format.name == name,
      orElse: () => MessageTimeFormat.h24,
    );
  }
}
