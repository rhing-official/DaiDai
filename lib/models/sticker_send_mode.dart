/// ペタピタ（スタンプ）をタップしてから送信するまでの挙動。
enum StickerSendMode {
  /// LINE型（標準）：1回目のタップで拡大プレビューを表示し、同じペタピタを
  /// もう一度タップすると送信する。日本国内ではLINEの2タップ方式の方が
  /// 馴染みがあるため既定にする（2026-08-13）。
  line,

  /// Discord型：1回のタップで即座に送信する。
  discord;

  static StickerSendMode fromName(String? name) {
    return StickerSendMode.values.firstWhere(
      (mode) => mode.name == name,
      orElse: () => StickerSendMode.line,
    );
  }
}
