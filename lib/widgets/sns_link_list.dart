import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/profile_material.dart';
import 'profile_card_view.dart' show displaySnsLinkUrl;

/// 他人のプロフィールカードダイアログで、カードの下に独立して表示する
/// タップ可能なSNSリンク一覧（2026-09-24追加）。カード内の
/// [ProfileCardView]が使う`SnsLinksInline`はタップ＝編集ポップアップを
/// 開く用途（工房の編集画面向け）なのに対し、こちらはタップ＝
/// `launchUrl`で外部ブラウザ/アプリへジャンプする用途のため、責務が
/// 異なるものとして別クラスにしている（`link_preview_card.dart`の
/// `_open()`と同じ起動パターン）。
class SnsLinkList extends StatelessWidget {
  const SnsLinkList({required this.links, super.key});

  final List<SnsLink> links;

  Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    if (links.isEmpty) return const SizedBox.shrink();
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final link in links)
          InkWell(
            onTap: () => _open(link.url),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.link, size: 16, color: colorScheme.primary),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      displaySnsLinkUrl(link.url),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: colorScheme.primary),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
