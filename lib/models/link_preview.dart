/// メッセージ本文に含まれるURL先のリンクプレビュー（タイトル・説明文・
/// サムネイル画像）。`api/url-preview.js`のレスポンスに対応する。
class LinkPreview {
  const LinkPreview({
    required this.url,
    this.title,
    this.description,
    this.image,
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
}
