import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/link_preview_provider.dart';

/// メッセージ本文に含まれるURLの下に表示する、タイトル・説明文・
/// サムネイル画像のプレビューカード。取得中は何も表示せず、取得に失敗
/// した場合やタイトル等が何も取れなかった場合もカード自体を出さない
/// （メッセージ本文の表示はプレビューの有無に関わらず成立するため）。
class LinkPreviewCard extends ConsumerWidget {
  const LinkPreviewCard({required this.url, super.key});

  final String url;

  Future<void> _open() async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preview = ref.watch(linkPreviewProvider(url));
    final colorScheme = Theme.of(context).colorScheme;

    return preview.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (data) {
        if (data == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 300),
            child: Material(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: _open,
                child: Column(
                  // 画像はカード幅いっぱいに揃え、高さは元画像の縦横比に
                  // 応じて可変させる（クロップしない）。縦長・横長どちらの
                  // 画像でも不自然に切り取られないようにするため、固定の
                  // アスペクト比・BoxFit.coverは使わない。
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (data.image != null)
                      ConstrainedBox(
                        // 極端に縦長な画像が語らいの表示を占領しないための
                        // 安全策。この上限に達したときだけコーナーではなく
                        // 中央を基準にcoverでクロップする。
                        constraints: const BoxConstraints(maxHeight: 360),
                        child: Image.network(
                          data.image!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) =>
                              const SizedBox.shrink(),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (data.title != null)
                            Text(
                              data.title!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onSurface,
                              ),
                            ),
                          if (data.description != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              data.description!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
