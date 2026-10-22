import 'package:flutter/material.dart';

import '../models/group_profile_card.dart';
import 'focal_circle_avatar.dart';
import 'focal_image.dart';

/// 広場のプロフィールカード（[GroupProfileCard]）を読み取り専用で描く。
/// `GroupProfileCardPopup`（編集画面）と同じレイアウト（背景画像＋暗転、左下に
/// アイコン・名前・一言）。語らい一覧のホバーカードで使う（2026-10-13）。
/// 編集ポップアップ側とは見た目を二重管理しているため、どちらかを変えたら
/// もう一方も合わせること。
class GroupProfileCardView extends StatelessWidget {
  const GroupProfileCardView({required this.card, super.key});

  final GroupProfileCard card;

  /// 基準サイズ（編集ポップアップと同じ4:5）。
  static const size = Size(280, 350);

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final background = card.backgroundImageUrl;
    final hasBackground = background != null;
    const padding = 20.0;
    return Material(
      clipBehavior: Clip.antiAlias,
      borderRadius: BorderRadius.circular(16),
      color: colorScheme.surfaceContainerHighest,
      child: SizedBox(
        width: size.width,
        height: size.height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (hasBackground)
              FocalImage(url: background, focal: card.backgroundFocal),
            if (hasBackground)
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black54],
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                padding,
                padding,
                padding,
                padding * 1.8,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  FocalCircleAvatar(
                    radius: 32,
                    url: card.iconUrl,
                    focal: card.iconFocal,
                    foregroundColor: colorScheme.onSurfaceVariant,
                    fallback: const Icon(Icons.groups_outlined),
                  ),
                  const SizedBox(height: padding * 0.6),
                  Text(
                    card.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: hasBackground ? Colors.white : null,
                    ),
                  ),
                  if (card.description.isNotEmpty)
                    Text(
                      card.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        color: hasBackground
                            ? Colors.white70
                            : colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
