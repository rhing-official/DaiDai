import 'package:flutter/material.dart';

import '../models/profile_material.dart';

/// カード内のアイコン・余白・文字サイズは、カード自体の横幅（モバイルは
/// 狭い・PCは広い）に関わらず常にこの固定値を使う（2026-09-26変更）。
/// 以前は`width`に対する比率＋`.clamp()`で計算しており、クランプの上限が
/// `UserProfileCardDialog`の最大カード幅（480px）付近を想定して調整されて
/// いたため、それより広い工房カード一覧（最大640px）ではクランプに掛かって
/// 頭打ちになる一方、クランプに掛からないモバイル幅ではほぼ素の比率のまま
/// 表示され、同じカードなのにモバイルとPCで見た目が異なってしまっていた。
/// PC（頭打ち時）の見た目が良いとのユーザー判断により、その頭打ち値
/// （このクラスの各定数）をカード幅に関わらず常に使う固定サイズとして採用し、
/// SNS向けOGP画像生成（`api/og-image.mjs`）もこの値をCARD_WIDTH基準に
/// スケールして揃えている。
const double kProfileCardAvatarRadius = 64.0;
const double kProfileCardPadding = 32.0;
const double kProfileCardNicknameFontSize = 28.0;
const double kProfileCardStatusFontSize = 18.0;

/// 身だしなみ・工房で作るプロフィールカードの見た目そのもの
/// （背景画像＋アイコン・呼び名・ステメ・SNSリンクを左下にまとめた構成）を、
/// 工房のカード一覧（`_WorkshopCardSlot`）とプロフィールカードダイアログ
/// （`UserProfileCardDialog`）の両方から共通で使う。表示先ごとに手で
/// レイアウトを合わせ直すと（実際に2度ズレが起きた）、片方だけ更新されて
/// デザインが食い違うため、実際の描画コード自体を1箇所にまとめている。
///
/// カード内のアイコン半径・余白・文字サイズは、カード幅に関わらず常に
/// [kProfileCardAvatarRadius]等の固定値を使う。ズーム編集画面
/// （`profile_tab.dart`の`_CardZoomEditor`）も同じ定数を使っている。
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
    this.fontFamily,
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

  /// カード作者が蔵で明示的に選んだフォントデザイン（2026-09-26追加）。
  /// nullなら「システムと同じ」として何も指定せず、周囲の`Theme`（＝見る側の
  /// 端末のフォントデザイン設定）をそのまま継承する。非nullの場合、見る側の
  /// 設定に関わらずこのフォントで固定表示する。呼び出し側で
  /// `AppUser.effectiveFontDesignFor(conversationId)?.fontFamily`等から解決する。
  final String? fontFamily;

  @override
  Widget build(BuildContext context) {
    const avatarRadius = kProfileCardAvatarRadius;
    const padding = kProfileCardPadding;
    const nicknameFontSize = kProfileCardNicknameFontSize;
    const statusFontSize = kProfileCardStatusFontSize;
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
              // アイコン・呼び名・一言・URLのサイズを固定値にしたことで、
              // 想定より極端に狭いカード幅（呼び出し側のclamp下限等）では
              // 収まりきらない可能性があるため、その場合だけ自動的に
              // 縮小してオーバーフローを防ぐ（拡大はしない）。
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.bottomLeft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    CircleAvatar(
                      radius: avatarRadius,
                      backgroundImage: icon != null
                          ? NetworkImage(icon!.url)
                          : null,
                      backgroundColor: Colors.transparent,
                      foregroundColor: Theme.of(
                        context,
                      ).colorScheme.onSurfaceVariant,
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
                        fontFamily: fontFamily,
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
                          fontFamily: fontFamily,
                        ),
                      ),
                    if (snsLinks.isNotEmpty) ...[
                      SizedBox(height: padding * 0.3),
                      SnsLinksInline(
                        links: snsLinks,
                        iconSize: statusFontSize,
                        fontSize: statusFontSize * 0.9,
                        color: subtitleColor,
                        fontFamily: fontFamily,
                      ),
                    ],
                  ],
                ),
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
    this.fontFamily,
    super.key,
  });

  final List<SnsLink> links;
  final double iconSize;
  final double fontSize;
  final Color? color;

  /// 未登録時に表示するプレースホルダー文言。nullなら未登録時は何も表示しない。
  final String? placeholder;
  final VoidCallback? onTap;

  /// [ProfileCardView.fontFamily]参照。nullなら周囲の`Theme`を継承する。
  final String? fontFamily;

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
                style: TextStyle(
                  fontSize: fontSize,
                  color: color,
                  fontFamily: fontFamily,
                ),
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
                          style: TextStyle(
                            fontSize: fontSize,
                            color: color,
                            fontFamily: fontFamily,
                          ),
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

/// カード上に表示する際、URLをドメイン部分のみに短縮する。実際に保存・
/// 使用するURL自体（[SnsLink.url]）は変更しない（蔵ではフルパスのまま
/// 表示するが、カードに貼り付けた際はドメインまでの表示に短縮する、
/// 2026-09-24変更）。
String displaySnsLinkUrl(String url) {
  final host = Uri.tryParse(url)?.host;
  if (host == null || host.isEmpty) {
    // パース出来ない値（scheme無し等）は従来通りscheme部分だけ除去する。
    return url.replaceFirst(
      RegExp(r'^https?://(www\.)?', caseSensitive: false),
      '',
    );
  }
  return host.replaceFirst(RegExp(r'^www\.', caseSensitive: false), '');
}
