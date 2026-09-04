import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/link_preview.dart';
import '../providers/link_preview_provider.dart';
import '../theme/gekiga/gekiga_colors.dart';
import 'media_preview_frame.dart';

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
/// 分けている（2026-08-10追加）。フラットUIはアクセントカラーの縦バー・
/// 色付きタイトルでDiscordに近い配色、劇画UIはアクセントカラーを使わず
/// （劇画UI選択中はアクセントカラー自体変更不可という既存方針との整合）、
/// 他の劇画UI要素と同じ「モノクロボックス」意匠にする。
class LinkPreviewCard extends ConsumerWidget {
  const LinkPreviewCard({
    required this.url,
    required this.isGekiga,
    required this.isMe,
    super.key,
  });

  final String url;
  final bool isGekiga;
  final bool isMe;

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
              : _buildFlatCard(context, data),
        );
      },
    );
  }

  /// リンクプレビューのサムネイル画像。フラット/劇画共通で
  /// `mediaPreviewFrame`（吹き出し内の添付画像/動画と共通、2026-08-12
  /// 切り出し）を使い外枠を揃える。以前はフラット/劇画それぞれが独自に
  /// 角丸のロジックを持っており値がずれていた（フラット6px・劇画は
  /// `_GekigaPhotoMat`を使わない別実装）。再生アイコンの配色・枠線は
  /// 各UIスタイルの既存デザインのまま維持する。[showFrame]が`false`の場合
  /// （劇画UIのカード内に置く場合）は`mediaPreviewFrame`自体の枠線を出さず
  /// 角丸のクリップのみにする。カード自体が既に`GekigaStraightMonochromeBox`
  /// の枠を持っており、二重表示になるため（2026-09-04追加）。
  Widget _thumbnail(
    String imageUrl, {
    required bool isVideo,
    required bool isGekiga,
    bool showFrame = true,
  }) {
    final content = Stack(
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
              color: isGekiga
                  ? GekigaColors.panel.withValues(alpha: 0.6)
                  : Colors.black.withValues(alpha: 0.6),
              shape: BoxShape.circle,
              border: isGekiga
                  ? Border.all(color: GekigaColors.onPanel, width: 2)
                  : null,
            ),
            child: Icon(
              Icons.play_arrow,
              color: isGekiga ? GekigaColors.onPanel : Colors.white,
              size: isGekiga ? 26 : 28,
            ),
          ),
      ],
    );

    if (!showFrame) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(mediaPreviewContentRadius),
        child: content,
      );
    }
    return mediaPreviewFrame(isGekiga: isGekiga, isMe: isMe, child: content);
  }

  Widget _buildFlatCard(BuildContext context, LinkPreview data) {
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
                          _thumbnail(
                            data.image!,
                            isVideo: isVideo,
                            isGekiga: false,
                          ),
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
    final fg = isMe ? GekigaColors.panel : GekigaColors.onPanel;
    final subFg = fg.withValues(alpha: 0.75);

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 340),
      child: GekigaStraightMonochromeBox(
        isMe: isMe,
        child: Material(
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
                      style: TextStyle(fontWeight: FontWeight.bold, color: fg),
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
                    _thumbnail(
                      data.image!,
                      isVideo: isVideo,
                      isGekiga: true,
                      showFrame: false,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
