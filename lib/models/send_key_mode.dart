/// メッセージ入力欄でのEnterキーの挙動。
enum SendKeyMode {
  /// Enterで送信、Shift+Enterで改行（Discordなどでの一般的な既定）。
  enterToSend,

  /// Enterで改行、Ctrl+Enterで送信（Slackの代替設定と同じ考え方）。
  ctrlEnterToSend;

  static SendKeyMode fromName(String? name) {
    return SendKeyMode.values.firstWhere(
      (mode) => mode.name == name,
      orElse: () => SendKeyMode.enterToSend,
    );
  }
}
