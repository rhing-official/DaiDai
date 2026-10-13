import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/link_preview.dart';
import '../utils/web_link.dart';

abstract class LinkPreviewRepository {
  /// [url]先のOGPメタデータを取得する。取得に失敗した・何も取れなかった場合も
  /// URLだけのプレビューを返し、カードは必ず出す（2026-10-13、pixiv等が
  /// サーバーからのアクセスを弾いて空になりプレビューが付かなかったため）。
  /// 例外は投げない（チャット画面全体を壊さないため）。
  Future<LinkPreview?> fetchPreview(String url);
}

/// `cloudflare/worker.js`の`/api/url-preview`（Cloudflare Pages Worker）経由でOGPメタデータを取得する実装。
/// このAPIはFlutter Web開発サーバー（`flutter run -d web-server`）には
/// 存在しないため、常に本番デプロイ先（[kProductionWebOrigin]）を呼ぶ。
class HttpLinkPreviewRepository implements LinkPreviewRepository {
  @override
  Future<LinkPreview?> fetchPreview(String url) async {
    final endpoint = Uri.parse(
      '$kProductionWebOrigin/api/url-preview',
    ).replace(queryParameters: {'url': url});
    try {
      final response = await http
          .get(endpoint)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return LinkPreview(url: url);
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return LinkPreview.fromJson(json);
    } catch (e) {
      return LinkPreview(url: url);
    }
  }
}
