import 'package:flutter/material.dart';

import '../models/profile_material.dart';

/// 身だしなみ・工房で作るプロフィールカードの見た目そのもの
/// （背景画像＋アイコン・呼び名・ステメ・SNSリンクを左下にまとめた構成）を、
/// 工房のカード一覧（`_WorkshopCardSlot`）とプロフィールカードダイアログ
/// （`UserProfileCardDialog`）の両方から共通で使う。表示先ごとに手で
/// レイアウトを合わせ直すと（実際に2度ズレが起きた）、片方だけ更新されて
/// デザインが食い違うため、実際の描画コード自体を1箇所にまとめている。
///
/// カード内の比率（アイコン半径・余白・文字サイズ）は工房のカード一覧・
/// ズーム編集画面（`profile_tab.dart`の`_WorkshopCardSlot`/`_CardZoomEditor`）
/// と全く同じ計算式を使う。
class ProfileCardView extends StatelessWidget {
  const ProfileCardView({
    required this.width,
    required this.height,
    this.icon,
    this.background,
    required this.nickname,
    this.statusMessage,
    this.snsLinks = const [],
    this.borderRadius = const BorderRadius.all(Radius.circular(16)),
    super.key,
  });

  final double width;
  final double height;
  final ProfileMaterial? icon;
  final ProfileMaterial? background;

  /// カード内に表示する呼び名。未設定時のフォールバック（呼び名が無い場合に
  /// 何を出すか）は呼び出し側で解決してから渡す。
  final String nickname;

  /// nullなら行自体を表示しない。未設定時にプレースホルダー文言を出したい
  /// 画面（工房の編集ビュー等）は、呼び出し側でプレースホルダーを合成してから
  /// 渡すこと。
  final String? statusMessage;

  final List<SnsLink> snsLinks;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    final avatarRadius = (width * 0.13).clamp(18.0, 64.0);
    final padding = (width * 0.08).clamp(12.0, 32.0);
    final nicknameFontSize = (width * 0.075).clamp(14.0, 28.0);
    final statusFontSize = (width * 0.045).clamp(11.0, 18.0);
    final subtitleColor = background != null
        ? Colors.white70
        : Theme.of(context).colorScheme.onSurfaceVariant;

    return Material(
      clipBehavior: Clip.antiAlias,
      borderRadius: borderRadius,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: SizedBox(
        width: width,
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (background != null)
              Image.network(background!.url, fit: BoxFit.cover),
            if (background != null)
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
              padding: EdgeInsets.all(padding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  CircleAvatar(
                    radius: avatarRadius,
                    backgroundImage: icon != null
                        ? NetworkImage(icon!.url)
                        : null,
                    child: icon == null ? const Icon(Icons.person) : null,
                  ),
                  SizedBox(height: padding * 0.6),
                  Text(
                    nickname,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: nicknameFontSize,
                      fontWeight: FontWeight.bold,
                      color: background != null ? Colors.white : null,
                    ),
                  ),
                  if (statusMessage != null && statusMessage!.isNotEmpty)
                    Text(
                      statusMessage!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: statusFontSize,
                        color: subtitleColor,
                      ),
                    ),
                  if (snsLinks.isNotEmpty) ...[
                    SizedBox(height: padding * 0.3),
                    SnsLinksInline(
                      links: snsLinks,
                      iconSize: statusFontSize,
                      fontSize: statusFontSize * 0.9,
                      color: subtitleColor,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// カードに掲載するSNSのURL一覧の表示。1件ずつ縦に並べる（長いURLが混ざると
/// 1行" / "区切りでは後半が読めなくなるため）。[onTap]を渡すと編集画面
/// （工房のズーム編集）向けにタップでSNSリンクの選択ポップアップを開ける。
class SnsLinksInline extends StatelessWidget {
  const SnsLinksInline({
    required this.links,
    required this.iconSize,
    required this.fontSize,
    required this.color,
    this.placeholder,
    this.onTap,
    super.key,
  });

  final List<SnsLink> links;
  final double iconSize;
  final double fontSize;
  final Color? color;

  /// 未登録時に表示するプレースホルダー文言。nullなら未登録時は何も表示しない。
  final String? placeholder;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (links.isEmpty && placeholder == null) {
      return const SizedBox.shrink();
    }
    final content = links.isEmpty
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.link, size: iconSize, color: color),
              const SizedBox(width: 4),
              Text(
                placeholder!,
                style: TextStyle(fontSize: fontSize, color: color),
              ),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final link in links)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.link, size: iconSize, color: color),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          displaySnsLinkUrl(link.url),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: fontSize, color: color),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          );
    return onTap == null
        ? content
        : GestureDetector(onTap: onTap, child: content);
  }
}

/// 選択肢などに表示する際、先頭の`https://www.`（または`http://www.`・
/// `www.`なしの場合はscheme部分のみ）を取り除いた短い表示用文字列にする。
/// 実際に保存・使用するURL自体（[SnsLink.url]）は変更しない。
String displaySnsLinkUrl(String url) {
  return url.replaceFirst(
    RegExp(r'^https?://(www\.)?', caseSensitive: false),
    '',
  );
}
