import 'package:flutter/material.dart';

import '../theme/chalk/chalk_paint.dart';
import '../theme/chalk/chalk_theme.dart';

/// チョークスタイルのバナーの外枠（2026-11-27）。バナーを塗らず、黒板の地のまま、白いチョークの
/// 線（メニューチップの帯・大ブロックと同じ色・太さ）で囲む。中の文字・アイコンは、枠と同じチョークの色
/// （`onSurface`）で描くこと。アクセントカラーは文字に使わない。
///
/// 横いっぱいの帯だった所は、角丸の枠にして左右に余白を取る（直線の枠は、手描きの揺れで不要な線に
/// 見えるため）。[color]を渡すと、枠の内側をその色で塗る。画面の上に浮かぶバナーのように、下の
/// 内容が透けると読めない時だけ渡す。
class ChalkBannerFrame extends StatelessWidget {
  const ChalkBannerFrame({
    required this.child,
    this.color,
    this.margin = const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    this.radius = 12,
    super.key,
  });

  final Widget child;
  final Color? color;
  final EdgeInsetsGeometry margin;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(radius);
    return Padding(
      padding: margin,
      child: DecoratedBox(
        decoration: ChalkBoxDecoration(
          color: color,
          borderRadius: borderRadius,
          lineColor: Theme.of(context).colorScheme.onSurface,
          lineWidth: 2.2,
        ),
        // 波紋が枠からはみ出さないよう、角丸で切る。中身は、透明なMaterialの上に置く。
        child: ClipRRect(
          borderRadius: borderRadius,
          child: Material(type: MaterialType.transparency, child: child),
        ),
      ),
    );
  }
}

/// 一覧・メッセージ画面の簡素なバナー（承認待ち・友達申請の判断など）の外側。チョークなら
/// [ChalkBannerFrame]の枠、それ以外は従来の、少し濃い面の`Material`。
Widget plainBannerSurface(BuildContext context, {required Widget child}) {
  if (isChalkTheme(context)) return ChalkBannerFrame(child: child);
  return Material(
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    child: child,
  );
}
