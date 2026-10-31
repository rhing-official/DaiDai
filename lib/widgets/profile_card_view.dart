import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../models/profile_card.dart';
import '../models/profile_material.dart';
import '../utils/sns_icon.dart';
import 'focal_image.dart';

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

/// 上の固定値を前提にカードを描く基準サイズ（4:5）。元々モバイルで使っていた
/// カード幅（約400）の見た目を全表示の基準にする。表示幅がこれと違う場所（工房の編集画面・モバイル・語らいのホバー・招待ダイアログ・管理画面）は、
/// この大きさで描いてから表示幅へ縮小して比率を揃える（2026-10-13）。
const double kProfileCardDesignWidth = 400.0;
const double kProfileCardDesignHeight = 500.0;

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
    this.onOpenSnsLink,
    this.birthdayLabel,
    this.rhingSeedLabel,
    this.rhingSeedCopyText,
    this.rhingSeedCopiedLabel,
    this.borderRadius = const BorderRadius.all(Radius.circular(16)),
    this.fontFamily,
    this.backgroundFocal,
    this.iconFocal,
    this.layoutPreset,
    this.textAlign,
    this.fontColor,
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

  /// 渡すと、カード内のURLをタップして開ける（相手のカードを見るダイアログ用、2026-10-31）。
  final ValueChanged<SnsLink>? onOpenSnsLink;

  /// 誕生日の表示文字列（見る人の言語で整形済み、2026-10-23追加）。nullなら出さない。
  final String? birthdayLabel;

  /// Rhing Seedの表示文字列（`@seed`、2026-10-31追加）。nullなら出さない。
  final String? rhingSeedLabel;

  /// 渡すと、Rhing Seedの行をタップしてこの文字列をコピーできる（相手のカードを見る
  /// ダイアログ用）。コピー直後は[rhingSeedCopiedLabel]に1.5秒だけ置き換わる。
  final String? rhingSeedCopyText;
  final String? rhingSeedCopiedLabel;
  final BorderRadius borderRadius;

  /// カード作者が蔵で明示的に選んだフォントデザイン（2026-09-26追加）。
  /// nullなら「システムと同じ」として何も指定せず、周囲の`Theme`（＝見る側の
  /// 端末のフォントデザイン設定）をそのまま継承する。非nullの場合、見る側の
  /// 設定に関わらずこのフォントで固定表示する。呼び出し側で
  /// `AppUser.effectiveFontDesignFor(conversationId)?.fontFamily`等から解決する。
  final String? fontFamily;

  /// 背景画像・アイコンの中心指定（2026-10-11追加）。nullなら従来どおり中央。
  final ImageFocal? backgroundFocal;
  final ImageFocal? iconFocal;

  /// アイコン＋文字ブロックの配置と文字の揃え（2026-10-12追加）。nullなら従来どおり
  /// 左下・左揃え。
  final CardLayoutPreset? layoutPreset;
  final CardTextAlign? textAlign;

  /// カード内の文字の色（作者が選んだ色）。nullなら標準の白（#FFFFFF）。一言・URL・
  /// 誕生日は、この色を薄めた色で出す。
  final Color? fontColor;

  @override
  Widget build(BuildContext context) {
    // [width]×[height]は表示サイズ。中身は基準サイズで描いて縮小する。
    // 角丸は縮小後の大きさで効くよう外側で切り抜く。
    return ClipRRect(
      borderRadius: borderRadius,
      child: SizedBox(
        width: width,
        height: height,
        child: FittedBox(fit: BoxFit.contain, child: _buildBody(context)),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    const avatarRadius = kProfileCardAvatarRadius;
    const padding = kProfileCardPadding;
    const nicknameFontSize = kProfileCardNicknameFontSize;
    const statusFontSize = kProfileCardStatusFontSize;
    // 文字色の標準は白（2026-10-31）。作者が選んだ色があればその色。一言・URL・
    // 誕生日は、その色の75%の濃さ。
    final baseColor = fontColor ?? Colors.white;
    final subtitleColor = baseColor.withValues(alpha: baseColor.a * 0.75);
    final nicknameColor = baseColor;

    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: SizedBox(
        width: kProfileCardDesignWidth,
        height: kProfileCardDesignHeight,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (background != null)
              FocalImage(url: background!.url, focal: backgroundFocal),
            if (background != null)
              DecoratedBox(
                decoration: profileCardScrimDecoration(layoutPreset),
              ),
            ProfileCardContent(
              layoutPreset: layoutPreset,
              textAlign: textAlign,
              children: [
                ProfileCardAvatar(
                  icon: icon,
                  focal: iconFocal,
                  radius: avatarRadius,
                ),
                SizedBox(height: padding * 0.6),
                Text(
                  nickname,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: (textAlign ?? CardTextAlign.start).textAlign,
                  style: TextStyle(
                    fontSize: nicknameFontSize,
                    fontWeight: FontWeight.bold,
                    color: nicknameColor,
                    fontFamily: fontFamily,
                  ),
                ),
                if (statusMessage != null && statusMessage!.isNotEmpty)
                  Text(
                    statusMessage!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: (textAlign ?? CardTextAlign.start).textAlign,
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
                    onOpenLink: onOpenSnsLink,
                    fontSize: statusFontSize * 0.9,
                    color: subtitleColor,
                    fontFamily: fontFamily,
                    crossAxisAlignment:
                        (textAlign ?? CardTextAlign.start).crossAxisAlignment,
                  ),
                ],
                if (birthdayLabel != null && birthdayLabel!.isNotEmpty) ...[
                  SizedBox(height: padding * 0.3),
                  ProfileCardBirthdayLine(
                    label: birthdayLabel!,
                    fontSize: statusFontSize,
                    color: subtitleColor,
                    fontFamily: fontFamily,
                    crossAxisAlignment:
                        (textAlign ?? CardTextAlign.start).crossAxisAlignment,
                  ),
                ],
                if (rhingSeedLabel != null && rhingSeedLabel!.isNotEmpty) ...[
                  SizedBox(height: padding * 0.3),
                  ProfileCardRhingSeedLine(
                    label: rhingSeedLabel!,
                    copyText: rhingSeedCopyText,
                    copiedLabel: rhingSeedCopiedLabel,
                    fontSize: statusFontSize,
                    color: subtitleColor,
                    fontFamily: fontFamily,
                    crossAxisAlignment:
                        (textAlign ?? CardTextAlign.start).crossAxisAlignment,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 背景画像の上に重ねる暗幕。文字の置かれる側が濃くなるよう配置に追従する
/// （2026-10-12）。下寄せ=下が濃い（従来）／左上=上が濃い／中央=全体に薄く。
BoxDecoration profileCardScrimDecoration(CardLayoutPreset? preset) {
  if (preset == CardLayoutPreset.center) {
    return const BoxDecoration(color: Colors.black38);
  }
  final top = preset?.isTop ?? false;
  return BoxDecoration(
    gradient: LinearGradient(
      begin: top ? Alignment.bottomCenter : Alignment.topCenter,
      end: top ? Alignment.topCenter : Alignment.bottomCenter,
      colors: const [Colors.transparent, Colors.black54],
    ),
  );
}

/// カード内のアイコン・呼び名・一言・SNSの縦積みブロックを、配置プリセットと
/// 文字の揃えに従って置く共通の骨格（2026-10-12）。`ProfileCardView`と工房の
/// ズーム編集（`_CardZoomEditor`）の両方が使い、レイアウトの重複を避ける。
/// 内容が収まりきらない場合は自動的に縮小する（拡大はしない）。
class ProfileCardContent extends StatelessWidget {
  const ProfileCardContent({
    required this.children,
    this.layoutPreset,
    this.textAlign,
    super.key,
  });

  final List<Widget> children;
  final CardLayoutPreset? layoutPreset;
  final CardTextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(kProfileCardPadding),
      // アイコン・呼び名・一言・URLのサイズを固定値にしたことで、想定より極端に
      // 狭いカード幅では収まりきらない可能性があるため、その場合だけ自動的に
      // 縮小してオーバーフローを防ぐ。Hero飛行中（工房のズーム）も矩形が一瞬
      // 小さくなるが、FittedBoxならオーバーフロー警告そのものが起きない。
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: (layoutPreset ?? CardLayoutPreset.bottomLeft).alignment,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment:
              (textAlign ?? CardTextAlign.start).crossAxisAlignment,
          children: children,
        ),
      ),
    );
  }
}

/// カード内の誕生日の行（日付だけ、2026-10-23追加。SNSの下に置く）。工房の編集画面では
/// [onTap]で表示のオン/オフを切り替え、[dimmed]で「表示しない」状態を薄く示す。
class ProfileCardBirthdayLine extends StatelessWidget {
  const ProfileCardBirthdayLine({
    required this.label,
    required this.fontSize,
    required this.color,
    this.onTap,
    this.dimmed = false,
    this.fontFamily,
    this.crossAxisAlignment = CrossAxisAlignment.start,
    super.key,
  });

  final String label;
  final double fontSize;
  final Color? color;
  final VoidCallback? onTap;
  final bool dimmed;
  final String? fontFamily;
  final CrossAxisAlignment crossAxisAlignment;

  @override
  Widget build(BuildContext context) {
    final line = Opacity(
      opacity: dimmed ? 0.5 : 1,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              label,
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
    );
    final aligned = Align(
      alignment: switch (crossAxisAlignment) {
        CrossAxisAlignment.center => Alignment.center,
        CrossAxisAlignment.end => Alignment.centerRight,
        _ => Alignment.centerLeft,
      },
      widthFactor: 1,
      child: line,
    );
    return onTap == null
        ? aligned
        : GestureDetector(onTap: onTap, child: aligned);
  }
}

/// カード内のRhing Seedの行（`@seed`、2026-10-31追加。誕生日の下に置く）。工房の編集画面では
/// [onTap]で表示のオン/オフを切り替え、[dimmed]で「表示しない」状態を薄く示す。相手のカードを
/// 見る画面では[copyText]を渡すと、タップでコピーして[copiedLabel]を1.5秒だけ出す。
class ProfileCardRhingSeedLine extends StatefulWidget {
  const ProfileCardRhingSeedLine({
    required this.label,
    required this.fontSize,
    required this.color,
    this.onTap,
    this.copyText,
    this.copiedLabel,
    this.dimmed = false,
    this.fontFamily,
    this.crossAxisAlignment = CrossAxisAlignment.start,
    super.key,
  });

  final String label;
  final double fontSize;
  final Color? color;
  final VoidCallback? onTap;
  final String? copyText;
  final String? copiedLabel;
  final bool dimmed;
  final String? fontFamily;
  final CrossAxisAlignment crossAxisAlignment;

  @override
  State<ProfileCardRhingSeedLine> createState() =>
      _ProfileCardRhingSeedLineState();
}

class _ProfileCardRhingSeedLineState extends State<ProfileCardRhingSeedLine> {
  bool _copied = false;
  Timer? _resetTimer;

  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }

  void _copy() {
    Clipboard.setData(ClipboardData(text: widget.copyText!));
    setState(() => _copied = true);
    _resetTimer?.cancel();
    _resetTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return ProfileCardBirthdayLine(
      label: _copied ? (widget.copiedLabel ?? widget.label) : widget.label,
      fontSize: widget.fontSize,
      color: widget.color,
      dimmed: widget.dimmed,
      fontFamily: widget.fontFamily,
      crossAxisAlignment: widget.crossAxisAlignment,
      onTap: widget.onTap ?? (widget.copyText == null ? null : _copy),
    );
  }
}

/// カードに掲載するSNSのURL一覧の表示。1件ずつ縦に並べる（長いURLが混ざると
/// 1行" / "区切りでは後半が読めなくなるため）。[onTap]を渡すと編集画面
/// （工房のズーム編集）向けにタップでSNSリンクの選択ポップアップを開ける。
class SnsLinksInline extends StatelessWidget {
  const SnsLinksInline({
    required this.links,
    required this.fontSize,
    required this.color,
    this.placeholder,
    this.onTap,
    this.onOpenLink,
    this.fontFamily,
    this.crossAxisAlignment = CrossAxisAlignment.start,
    super.key,
  });

  /// URLの行をタップした時（nullなら行はタップできない）。
  final ValueChanged<SnsLink>? onOpenLink;

  final List<SnsLink> links;
  final double fontSize;
  final Color? color;

  /// 未登録時に表示するプレースホルダー文言。nullなら未登録時は何も表示しない。
  final String? placeholder;
  final VoidCallback? onTap;

  /// [ProfileCardView.fontFamily]参照。nullなら周囲の`Theme`を継承する。
  final String? fontFamily;

  /// 複数行のURLを互いにどちら側へ揃えるか（カードの文字の揃えに合わせる）。
  final CrossAxisAlignment crossAxisAlignment;

  @override
  Widget build(BuildContext context) {
    if (links.isEmpty && placeholder == null) {
      return const SizedBox.shrink();
    }
    final content = links.isEmpty
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
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
            crossAxisAlignment: crossAxisAlignment,
            mainAxisSize: MainAxisSize.min,
            children: [
              // 主要サービスはアイコンだけ（ドメインの文字は出さない）を横に並べ、
              // 一覧に無いサイトはドメインの文字を縦に並べる（2026-10-31）。
              if (links.any((l) => snsIconAssetFor(l.url) != null))
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Wrap(
                    spacing: 14,
                    runSpacing: 6,
                    alignment: switch (crossAxisAlignment) {
                      CrossAxisAlignment.center => WrapAlignment.center,
                      CrossAxisAlignment.end => WrapAlignment.end,
                      _ => WrapAlignment.start,
                    },
                    children: [
                      for (final link in links)
                        if (snsIconAssetFor(link.url) case final asset?)
                          _TappableLinkRow(
                            onTap: onOpenLink == null
                                ? null
                                : () => onOpenLink!(link),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 4,
                                horizontal: 2,
                              ),
                              child: SvgPicture.asset(
                                asset,
                                width: fontSize * 1.5,
                                height: fontSize * 1.5,
                                colorFilter: color == null
                                    ? null
                                    : ColorFilter.mode(color!, BlendMode.srcIn),
                              ),
                            ),
                          ),
                    ],
                  ),
                ),
              for (final link in links)
                if (snsIconAssetFor(link.url) == null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: _TappableLinkRow(
                      onTap: onOpenLink == null
                          ? null
                          : () => onOpenLink!(link),
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

/// カード内の円形アイコン。[focal]で円の中のどこを中心に見せるかを指定できる
/// （2026-10-11追加）。アイコンが無ければ人型のプレースホルダー。
class ProfileCardAvatar extends StatelessWidget {
  const ProfileCardAvatar({
    required this.icon,
    required this.radius,
    this.focal,
    super.key,
  });

  final ProfileMaterial? icon;
  final double radius;
  final ImageFocal? focal;

  @override
  Widget build(BuildContext context) {
    final icon = this.icon;
    if (icon == null) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: Colors.transparent,
        foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
        child: const Icon(Icons.person),
      );
    }
    return SizedBox(
      width: radius * 2,
      height: radius * 2,
      child: ClipOval(
        child: FocalImage(url: icon.url, focal: focal),
      ),
    );
  }
}

/// URLの1行。[onTap]があれば、タップで開ける（マウスではクリックできるカーソル）。
class _TappableLinkRow extends StatelessWidget {
  const _TappableLinkRow({required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (onTap == null) return child;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: child,
      ),
    );
  }
}
