import 'package:flutter/material.dart';

import '../../theme/gekiga/gekiga_colors.dart';
import '../../theme/gekiga/gekiga_shapes.dart';

/// 一対・広場・寄合一覧、設定・身だしなみのカテゴリ項目など、劇画スタイルの
/// メニューボックス全般に使う汎用ラッパー。メッセージ吹き出し
/// （`chat_screen.dart`の`_GekigaBubble`/`_GekigaBubblePainter`）と同じ
/// `handDrawnPolygonPath`ベースの手描き風ギザギザ枠を、任意の子ウィジェットに
/// 適用する（2026-07-30新規、`_GekigaBubble`自体は変更しない独立実装）。
///
/// [selected]がfalseなら黒地白枠（`GekigaColors.panel`/`onPanel`）、
/// trueなら反転して白地黒枠にする。[seed]は形状を安定させるための値
/// （呼び出し元が会話id等の`hashCode`を渡す想定）。
///
/// 枠の幅は[child]の実サイズにそのまま追従する（`CustomPaint`は子の
/// レイアウト結果のサイズを使う）。`Row`+`Flexible`で親から渡された幅を
/// 緩め、[child]が横いっぱいに広がろうとしない限り文字量に応じて可変になる
/// （2026-07-30追加）。**[child]には`ListTile`を渡さないこと** — `ListTile`は
/// 常に親の最大幅まで広がる仕様で、幅の緩和だけでは縮まらない
/// （下記[GekigaMenuTile]を参照）。
class GekigaPanelBox extends StatelessWidget {
  const GekigaPanelBox({
    required this.child,
    required this.seed,
    this.selected = false,
    super.key,
  });

  final Widget child;
  final int seed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Flexible(
          child: CustomPaint(
            painter: _GekigaPanelBoxPainter(seed: seed, selected: selected),
            child: child,
          ),
        ),
      ],
    );
  }
}

class _GekigaPanelBoxPainter extends CustomPainter {
  const _GekigaPanelBoxPainter({required this.seed, required this.selected});

  final int seed;
  final bool selected;

  @override
  void paint(Canvas canvas, Size size) {
    final path = handDrawnPolygonPath(
      [
        Offset.zero,
        Offset(size.width, 0),
        Offset(size.width, size.height),
        Offset(0, size.height),
      ],
      seed,
      // 吹き出し（_GekigaBubblePainter、jitter: 3.2）より控えめにする。
      // リスト項目は横長で複数個が縦に並ぶため、同じ強さのギザギザだと
      // 読みにくくなるため。
      jitter: 2.4,
      segmentsPerEdge: 5,
    );
    final fillColor = selected ? GekigaColors.onPanel : GekigaColors.panel;
    final strokeColor = selected ? GekigaColors.panel : GekigaColors.onPanel;
    canvas.drawPath(path, Paint()..color = fillColor);
    canvas.drawPath(
      path,
      Paint()
        ..color = strokeColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _GekigaPanelBoxPainter oldDelegate) =>
      oldDelegate.seed != seed || oldDelegate.selected != selected;
}

/// `ListTile`の代わりに使う、劇画スタイル専用の可変幅メニュー行
/// （アイコン＋タイトル／サブタイトル＋末尾ウィジェット）。
///
/// `ListTile`は常に親から渡された最大幅まで広がる仕様で、内部のタイトル
/// 部分も`Expanded`前提のため、`IntrinsicWidth`と組み合わせても文字が
/// 1文字ずつ縦に折り返される不具合が出る（2026-07-30に実機確認済み）。
/// メッセージ吹き出しが同じ理由で`ListTile`を使わず`Row`/`Column`を
/// 自前実装しているのと同じ理由で、こちらも`Row(mainAxisSize.min)`で
/// 独自に組んでいる。
class GekigaMenuTile extends StatelessWidget {
  const GekigaMenuTile({
    required this.seed,
    required this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.selected = false,
    this.onTap,
    super.key,
  });

  final int seed;
  final Widget leading;
  final Widget title;
  final Widget? subtitle;
  final Widget? trailing;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? GekigaColors.panel : GekigaColors.onPanel;
    return GekigaPanelBox(
      seed: seed,
      selected: selected,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconTheme.merge(
                  data: IconThemeData(color: fg),
                  child: leading,
                ),
                const SizedBox(width: 16),
                Flexible(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DefaultTextStyle.merge(
                        style: TextStyle(color: fg),
                        child: title,
                      ),
                      if (subtitle != null)
                        DefaultTextStyle.merge(
                          style: TextStyle(color: fg, fontSize: 12),
                          child: subtitle!,
                        ),
                    ],
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 12),
                  IconTheme.merge(
                    data: IconThemeData(color: fg),
                    child: trailing!,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
