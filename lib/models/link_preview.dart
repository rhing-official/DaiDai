import 'app_user.dart';
import 'group_profile_card.dart';

/// メッセージ本文に含まれるURL先のリンクプレビュー（タイトル・説明文・
/// サムネイル画像）。`api/url-preview.js`のレスポンスに対応する。
class LinkPreview {
  const LinkPreview({
    required this.url,
    this.title,
    this.description,
    this.image,
    this.inviteUser,
    this.inviteGroup,
  });

  factory LinkPreview.fromJson(Map<String, dynamic> json) => LinkPreview(
    url: json['url'] as String,
    title: json['title'] as String?,
    description: json['description'] as String?,
    image: json['image'] as String?,
  );

  final String url;
  final String? title;
  final String? description;
  final String? image;

  /// DaiDai自身の招待リンクの時の、招待した人／広場。渡されると、リンクカードは画像の
  /// 代わりに、プロフィールカードそのまま（背景・アイコンのGIFも再生される）を描く
  /// （2026-11-09、サーバーが作るOGP画像は静止画になる為）。
  final AppUser? inviteUser;
  final GroupProfileCard? inviteGroup;
}
