/// お便り（運営の発信元）の名前・アイコン（`system/official`、2026-10-10追加）。
/// お便りは住人（`users`）ではないため`rhingSeed`・呼び名・蔵を持たず、
/// 表示に必要な名前とアイコンだけをこの1件のドキュメントに持つ。
class OfficialProfile {
  const OfficialProfile({this.name = defaultName, this.iconUrl});

  /// `system/official`が未作成の間に表示する名前。
  static const defaultName = 'お便り';

  /// お便りの発信元として`Message.senderId`に使う値（`users`を引かない
  /// 目印、`chat_screen.dart`の`kSystemSenderPrefix`で始まる）。
  static const senderId = 'system:official';

  final String name;
  final String? iconUrl;

  factory OfficialProfile.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const OfficialProfile();
    final name = json['name'] as String?;
    return OfficialProfile(
      name: (name == null || name.isEmpty) ? defaultName : name,
      iconUrl: json['iconUrl'] as String?,
    );
  }
}
