import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/link_preview.dart';
import '../providers/link_preview_provider.dart';
import '../theme/gekiga/gekiga_colors.dart';
import '../widgets/gekiga/gekiga_panel_box.dart';

/// 動画リンクと判定するホスト名（サムネイルに再生アイコンを重ねる対象）。
/// OGPからは`og:type`等を取得していないため、簡易的にホスト名で判定する。
const _videoHosts = ['youtube.com', 'youtu.be', 'vimeo.com'];

/// メッセージ本文に含まれるURLの下に表示する、タイトル・説明文・
/// サムネイル画像のプレビューカード。取得中は何も表示せず、取得に失敗
/// した場合やタイトル等が何も取れなかった場合もカード自体を出さない
/// （メッセージ本文の表示はプレビューの有無に関わらず成立するため）。
///
/// Discordの埋め込みカード（サイト名→タイトル→説明文→画像、動画には
/// 再生アイコン）を参考にした構成に統一しつつ、外枠・配色はUIスタイルごとに
/// 分けている（2026-08-10追加）。シンプルUIはアクセントカラーの縦バー・
/// 色付きタイトルでDiscordに近い配色、劇画UIはアクセントカラーを使わず
/// （劇画UI選択中はアクセントカラー自体変更不可という既存方針との整合）、
/// 他の劇画UI要素と同じ「モノクロボックス」意匠にする。
class LinkPreviewCard extends ConsumerWidget {
  const LinkPreviewCard({required this.url, required this.isGekiga, super.key});

  final String url;
  final bool isGekiga;

  Future<void> _open() async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  /// サイト名の代わりに表示するホスト名（`www.`は除去）。OGPの
  /// `og:site_name`はサーバー側で取得していないため、クライアント側で
  /// URLから算出する。
  String? _hostLabel() {
    final host = Uri.tryParse(url)?.host;
    if (host == null || host.isEmpty) return null;
    return host.startsWith('www.') ? host.substring(4) : host;
  }

  bool _looksLikeVideo() {
    final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
    return _videoHosts.any(host.contains);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preview = ref.watch(linkPreviewProvider(url));

    return preview.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (data) {
        if (data == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: isGekiga
              ? _buildGekigaCard(context, data)
              : _buildSimpleCard(context, data),
        );
      },
    );
  }

  Widget _thumbnail(String imageUrl, {required bool isVideo}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Stack(
        alignment: Alignment.center,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 200),
            child: Image.network(
              imageUrl,
              fit: BoxFit.cover,
              width: double.infinity,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          ),
          if (isVideo)
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.play_arrow,
                color: Colors.white,
                size: 28,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSimpleCard(BuildContext context, LinkPreview data) {
    final colorScheme = Theme.of(context).colorScheme;
    final host = _hostLabel();
    final isVideo = _looksLikeVideo();

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: Material(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _open,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(width: 4, color: colorScheme.primary),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (host != null)
                          Text(
                            host,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        if (data.title != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            data.title!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: colorScheme.primary,
                            ),
                          ),
                        ],
                        if (data.description != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            data.description!,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                        if (data.image != null) ...[
                          const SizedBox(height: 8),
                          _thumbnail(data.image!, isVideo: isVideo),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGekigaCard(BuildContext context, LinkPreview data) {
    final host = _hostLabel();
    final isVideo = _looksLikeVideo();
    final subFg = GekigaColors.onPanel.withValues(alpha: 0.75);

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 340),
      child: GekigaJointedTileList(
        seeds: [url.hashCode],
        selectedFlags: const [false],
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _open,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (host != null)
                      Text(
                        host,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: subFg),
                      ),
                    if (data.title != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        data.title!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: GekigaColors.onPanel,
                        ),
                      ),
                    ],
                    if (data.description != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        data.description!,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: subFg),
                      ),
                    ],
                    if (data.image != null) ...[
                      const SizedBox(height: 8),
                      _gekigaThumbnail(data.image!, isVideo: isVideo),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// シンプルUIの[_thumbnail]と異なり、他の劇画UI要素（`GekigaPhotoFrame`
  /// 等）と同じ「白い余白（マット）に写真を余白付きで収める」構成にする
  /// （2026-08-10変更。以前は黒いモノクロボックスに直接画像を埋め込んでおり、
  /// 動画サムネイルの黒レターボックス部分が背景と同化して見えていた）。
  /// 動画の再生アイコンは「黒地・白枠・白アイコン」のモノクロ円のまま、
  /// 明るい画像の上でも視認しやすいよう半透明にする。
  Widget _gekigaThumbnail(String imageUrl, {required bool isVideo}) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Stack(
          alignment: Alignment.center,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: Image.network(
                imageUrl,
                fit: BoxFit.cover,
                width: double.infinity,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
            if (isVideo)
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: GekigaColors.panel.withValues(alpha: 0.6),
                  shape: BoxShape.circle,
                  border: Border.all(color: GekigaColors.onPanel, width: 2),
                ),
                child: const Icon(
                  Icons.play_arrow,
                  color: GekigaColors.onPanel,
                  size: 26,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
