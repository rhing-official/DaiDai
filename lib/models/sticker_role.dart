/// メッセージ内容に応じたペタピタ提案（`lib/utils/sticker_suggestion.dart`）
/// で使う役割定義（2026-09-05追加）。「嬉しい」「挨拶」等、感情・場面を
/// 表すカテゴリ1件につき1つの[StickerRole]を持ち、[keywords]に紐付いた
/// 語のいずれかがメッセージ本文に含まれると、[Sticker.roles]でこの
/// [roleId]を持つペタピタが提案候補になる。アプリ再配布無しでキーワードを
/// 調整できるよう、コード内定数ではなくFirestoreの`stickerRoles`
/// コレクションで保持する（`StickerRepository.watchRoles()`参照）。
class StickerRole {
  const StickerRole({
    required this.roleId,
    required this.name,
    required this.keywords,
  });

  final String roleId;
  final String name;
  final List<String> keywords;

  factory StickerRole.fromJson(String roleId, Map<String, dynamic> json) {
    return StickerRole(
      roleId: roleId,
      name: json['name'] as String,
      keywords: (json['keywords'] as List<dynamic>? ?? [])
          .map((e) => e as String)
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {'name': name, 'keywords': keywords};
}
