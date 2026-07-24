/// DaiDai独自の世界観用語（蔵・工房・一対・広場など）を使うか、
/// 一般的なアプリで馴染みのある利便性重視の用語を使うかの切り替え。
/// 表示言語（日本語／English）とは独立した軸で、`docs/マップ.md`の
/// 対訳表（2×2: 言語×用語）に対応する。
enum TerminologyStyle {
  worldview,
  convenience;

  static TerminologyStyle fromName(String? name) {
    return TerminologyStyle.values.firstWhere(
      (style) => style.name == name,
      orElse: () => TerminologyStyle.worldview,
    );
  }
}
