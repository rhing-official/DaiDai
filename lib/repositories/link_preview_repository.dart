import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

import '../models/link_preview.dart';
import '../utils/web_link.dart';

abstract class LinkPreviewRepository {
  /// [url]先のOGPメタデータを取得する。取得に失敗した・何も取れなかった場合も
  /// URLだけのプレビューを返し、カードは必ず出す（2026-10-13、pixiv等が
  /// サーバーからのアクセスを弾いて空になりプレビューが付かなかった為）。
  /// 例外は投げない（チャット画面全体を壊さない為）。
  Future<LinkPreview?> fetchPreview(String url);
}

/// `cloudflare/worker.js`の`/api/url-preview`（Cloudflare Pages Worker）経由でOGPメタデータを取得する実装。
/// このAPIはFlutter Web開発サーバー（`flutter run -d web-server`）には
/// 存在しない為、常に本番デプロイ先（[kProductionWebOrigin]）を呼ぶ。
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

/// DaiDai自身の招待リンク（`/invite/:rhingSeed`・`/join/:groupId`）のプレビューを、
/// 外部のOGP画像（サーバーが作る静止画PNG）ではなく、公開プレビューの情報から
/// アプリ内で組み立てる（2026-11-09）。OGP画像は`sharp`でPNGに変換する時にGIFの
/// 最初の1コマだけになる為、アイコンにGIFを設定していてもチャットのカードでは
/// 動かなかった。ここでは元のアイコンのURLをそのまま画像として渡し、`Image.network`が
/// GIFを再生できるようにする。見つからない・失敗した時は[inner]（従来のOGP）へ戻す。
/// 外部のSNSに貼られた時のOGP画像は、静止画のまま（多くのSNSは動かさない）。
class InviteAwareLinkPreviewRepository implements LinkPreviewRepository {
  InviteAwareLinkPreviewRepository({
    required this.inner,
    required this.userPreview,
    required this.groupPreview,
  });

  final LinkPreviewRepository inner;

  /// Rhing Seedから、呼び名・一言・アイコンのURLを返す。無ければnull。
  final Future<LinkPreview?> Function(String url, String rhingSeed) userPreview;

  /// 広場のidから、名前・説明・アイコンのURLを返す。無ければnull。
  final Future<LinkPreview?> Function(String url, String groupId) groupPreview;

  /// 招待リンクのパス（`/invite/x`・`/join/x`、末尾に版識別子などが付いても良い）から
  /// 種類とidを取り出す。DaiDaiのホスト以外・招待以外はnull。
  static ({String kind, String id})? parseInvite(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasAuthority) return null;
    final ownHosts = {Uri.parse(kProductionWebOrigin).host};
    if (kIsWeb) ownHosts.add(Uri.base.host);
    if (!ownHosts.contains(uri.host)) return null;
    final segments = uri.pathSegments.where((e) => e.isNotEmpty).toList();
    if (segments.length < 2) return null;
    if (segments[0] != 'invite' && segments[0] != 'join') return null;
    return (kind: segments[0], id: Uri.decodeComponent(segments[1]));
  }

  @override
  Future<LinkPreview?> fetchPreview(String url) async {
    final invite = parseInvite(url);
    if (invite != null) {
      try {
        final preview = invite.kind == 'invite'
            ? await userPreview(url, invite.id.toLowerCase())
            : await groupPreview(url, invite.id);
        if (preview != null) return preview;
      } catch (_) {
        // 取れなければ従来のOGPへ戻す。
      }
    }
    return inner.fetchPreview(url);
  }
}
