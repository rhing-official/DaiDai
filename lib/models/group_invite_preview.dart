/// `groupInvites/{groupId}`に保存する、広場の公開プレビュー情報。
/// 招待リンクを開いた（まだメンバーではない）相手や、外部SNSのリンク展開
/// （OGP）に見せるための最小限の情報のみを持つ（メンバー一覧・メッセージ等は
/// 一切含まない）。広場のプロフィールカードが変わるたびに同期して書き込む。
class GroupInvitePreview {
  const GroupInvitePreview({
    required this.name,
    this.description = '',
    this.iconUrl,
  });

  final String name;
  final String description;
  final String? iconUrl;

  factory GroupInvitePreview.fromJson(Map<String, dynamic> json) {
    return GroupInvitePreview(
      name: json['name'] as String,
      description: json['description'] as String? ?? '',
      iconUrl: json['iconUrl'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'description': description,
      'iconUrl': iconUrl,
    };
  }
}
