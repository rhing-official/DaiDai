/// `userInvites/{rhingSeed}`に保存する、個人の縁結び招待リンクの公開プレビュー。
/// 外部SNSのリンク展開（OGP）に見せるための最小限の情報のみを持つ
/// （友達一覧・語らいの内容などは一切含まない）。蔵のアイコン・呼び名・
/// アクティブな工房カードが変わるたびに同期して書き込む。
class UserInvitePreview {
  const UserInvitePreview({
    required this.userId,
    this.nickname,
    this.iconUrl,
    this.statusMessage,
    this.backgroundImageUrl,
    this.snsLinkUrls = const [],
    this.layoutPreset,
    this.textAlign,
  });

  final String userId;
  final String? nickname;
  final String? iconUrl;
  final String? statusMessage;

  /// OGP画像を工房のプロフィールカードそのままの見た目で生成するために使う
  /// （`api/og-image.js`が参照する）。アクティブな工房カードの`backgroundImageId`・
  /// `snsLinkIds`から解決した値。カード未選択時はnull/空のまま。
  final String? backgroundImageUrl;
  final List<String> snsLinkUrls;

  /// アクティブな工房カードの配置プリセットと文字の揃え（`CardLayoutPreset.name`
  /// /`CardTextAlign.name`、2026-10-12追加）。nullなら従来の左下・左揃え。
  final String? layoutPreset;
  final String? textAlign;

  factory UserInvitePreview.fromJson(Map<String, dynamic> json) {
    return UserInvitePreview(
      userId: json['userId'] as String,
      nickname: json['nickname'] as String?,
      iconUrl: json['iconUrl'] as String?,
      statusMessage: json['statusMessage'] as String?,
      backgroundImageUrl: json['backgroundImageUrl'] as String?,
      snsLinkUrls: (json['snsLinkUrls'] as List?)?.cast<String>() ?? const [],
      layoutPreset: json['layoutPreset'] as String?,
      textAlign: json['textAlign'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'nickname': nickname,
      'iconUrl': iconUrl,
      'statusMessage': statusMessage,
      'backgroundImageUrl': backgroundImageUrl,
      'snsLinkUrls': snsLinkUrls,
      if (layoutPreset != null) 'layoutPreset': layoutPreset,
      if (textAlign != null) 'textAlign': textAlign,
    };
  }
}
