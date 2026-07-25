/// 語らいのメッセージ表示スタイル。端末ごとの個人設定で、自分の画面の
/// 見た目だけを変える（相手の語らいの表示には一切影響しない）。
enum ChatLayoutStyle {
  /// 自分のメッセージは右寄せ・相手は左寄せ。自分のアイコンは表示しない。
  /// 一対（1対1）では、相手のアイコン・呼び名も表示しない
  /// （話し相手が1人しかいないため、繰り返し表示する意味が薄いという判断）。
  /// 広場（グループ）では、相手（送信者）のアイコン・呼び名は引き続き表示する。
  sideBySide,

  /// 自分・相手ともに左寄せで、常にアイコン・呼び名を表示する。
  allLeft;

  static ChatLayoutStyle fromName(String? name) {
    return ChatLayoutStyle.values.firstWhere(
      (style) => style.name == name,
      orElse: () => ChatLayoutStyle.sideBySide,
    );
  }
}
