import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/link_preview.dart';
import '../utils/web_link.dart';

abstract class LinkPreviewRepository {
  /// [url]先のOGPメタデータを取得する。取得自体に失敗した場合はnullを返す
  /// （メッセージ本文の表示自体はプレビューが無くても成立するため、
  /// 例外を投げてチャット画面全体を壊さないようにする）。
  Future<LinkPreview?> fetchPreview(String url);
}

/// `api/url-preview.js`（Vercel Function）経由でOGPメタデータを取得する実装。
/// このAPIはFlutter Web開発サーバー（`flutter run -d web-server`）には
/// 存在しないため、常に本番デプロイ先（[kProductionWebOrigin]）を呼ぶ。
class HttpLinkPreviewRepository implements LinkPreviewRepository {
  @override
  Future<LinkPreview?> fetchPreview(String url) async {
    final endpoint = Uri.parse('$kProductionWebOrigin/api/url-preview')
        .replace(queryParameters: {'url': url});
    try {
      final response = await http
          .get(endpoint)
          .timeout(const Duration(seconds: 6));
      if (response.statusCode != 200) return null;
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final preview = LinkPreview.fromJson(json);
      return preview.hasContent ? preview : null;
    } catch (e) {
      return null;
    }
  }
}
