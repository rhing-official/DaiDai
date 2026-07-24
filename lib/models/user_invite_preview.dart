/// `userInvites/{rhingId}`に保存する、個人の縁結び招待リンクの公開プレビュー。
/// 外部SNSのリンク展開（OGP）に見せるための最小限の情報のみを持つ
/// （友達一覧・語らいの内容などは一切含まない）。蔵のアイコン・呼び名が
/// 変わるたびに同期して書き込む。
class UserInvitePreview {
  const UserInvitePreview({
    required this.userId,
    this.nickname,
    this.iconUrl,
  });

  final String userId;
  final String? nickname;
  final String? iconUrl;

  factory UserInvitePreview.fromJson(Map<String, dynamic> json) {
    return UserInvitePreview(
      userId: json['userId'] as String,
      nickname: json['nickname'] as String?,
      iconUrl: json['iconUrl'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'nickname': nickname,
      'iconUrl': iconUrl,
    };
  }
}
