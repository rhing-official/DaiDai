import 'package:flutter/material.dart';

/// 画像・動画プレビューの外枠。フラットUI/劇画UI共通で使う（2026-08-12
/// 切り出し）。以前は`chat_screen.dart`（吹き出し内の添付画像/動画）と
/// `link_preview_card.dart`（リンクプレビューのサムネイル）がそれぞれ
/// 独自に角丸のロジックを実装しており、値がずれて「同じ画像なのに角丸な
/// 時と直角な時がある」不具合の原因になっていた。
Widget mediaPreviewFrame({
  required bool isGekiga,
  required bool isMe,
  required Widget child,
}) {
  if (!isGekiga) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(mediaPreviewContentRadius),
      child: child,
    );
  }
  return GekigaStraightMonochromeBox(
    isMe: isMe,
    padding: const EdgeInsets.all(_matWidth),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(mediaPreviewContentRadius),
      child: child,
    ),
  );
}

/// [mediaPreviewFrame]の内容部分の角丸半径。既にこの枠に包まれた画像/動画を
/// さらに別の自前枠（URLプレビューカード等）の中に置く場合、`mediaPreviewFrame`
/// 自体は使わずこの定数だけ流用して二重枠を避けることがある
/// （`link_preview_card.dart`の`_thumbnail`参照）。
const mediaPreviewContentRadius = 8.0;
const _matWidth = 10.0;

/// 劇画UIの直角モノクロボックス（白枠→黒枠→地色→中身、`isMe`で白黒反転）。
/// 通常の吹き出し（`_GekigaBubblePainter`/`MonochromeBoxPainter`）と同じ
/// 配色ロジック（自分=外枠白・中枠黒・地色白、相手=外枠黒・中枠白・地色黒）
/// だが、歪んだ平行四辺形ではなく完全な直角の矩形として描く。自前の枠を
/// 持つカード全般（写真/動画添付・予定追加通知・マークダウン/URL
/// プレビューカード）で共通利用する（2026-09-04追加）。
class GekigaStraightMonochromeBox extends StatelessWidget {
  const GekigaStraightMonochromeBox({
    required this.isMe,
    required this.child,
    this.padding = EdgeInsets.zero,
    super.key,
  });

  final bool isMe;
  final Widget child;
  final EdgeInsetsGeometry padding;

  static const _outerThickness = 3.0;
  static const _middleThickness = 3.0;

  @override
  Widget build(BuildContext context) {
    final outer = isMe ? Colors.white : Colors.black;
    final middle = isMe ? Colors.black : Colors.white;
    final fill = isMe ? Colors.white : Colors.black;
    return ColoredBox(
      color: outer,
      child: Padding(
        padding: const EdgeInsets.all(_outerThickness),
        child: ColoredBox(
          color: middle,
          child: Padding(
            padding: const EdgeInsets.all(_middleThickness),
            child: ColoredBox(
              color: fill,
              child: Padding(padding: padding, child: child),
            ),
          ),
        ),
      ),
    );
  }
}
