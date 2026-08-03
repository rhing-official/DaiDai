import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/font_design.dart';
import '../../providers/font_design_provider.dart';
import '../../theme/gekiga/gekiga_colors.dart';
import '../../theme/gekiga/gekiga_fonts.dart';
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
///
/// 左側に[_leftInset]分の余白を入れて右へずらしている（2026-08-03追加）。
/// 以前は左詰め（`Row`既定の`mainAxisAlignment.start`）のままだったため、
/// 手描き風のギザギザ枠（`handDrawnPolygonPath`のjitter・線の太さ分、
/// 実際の描画がこのウィジェットのレイアウト上のサイズより数px外側にはみ出す
/// ことがある）が、親コンテナの左端ぎりぎり（特に左右パディングの無い
/// モバイル幅の一覧）で画面端からはみ出して見える不具合があった。
///
/// 幅いっぱいに広げる`expand`オプションを設定・身だしなみのカテゴリ一覧に
/// 試験的に追加したことがあったが、「横幅は可変のままがいい」との
/// フィードバックを受けて削除した（2026-08-03、可変幅のみに一本化）。
const _leftInset = 12.0;

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
        const SizedBox(width: _leftInset),
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
class GekigaMenuTile extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final fg = selected ? GekigaColors.panel : GekigaColors.onPanel;
    // タイトル（メニュー項目名）にはフォントデザイン「劇画」選択時に見出し用
    // フォントを当てる。サブタイトル（説明文）は対象外（2026-08-03追加）。
    final isFontDesignGekiga =
        ref.watch(fontDesignProvider) == FontDesign.gekiga;
    final titleStyle = TextStyle(
      color: fg,
      fontFamily: isFontDesignGekiga ? GekigaFonts.menuFontFamily : null,
    );
    return GekigaPanelBox(
      seed: seed,
      selected: selected,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            // シンプルスタイルの`ListTile`（既定で1行あたり約56dp）との縦幅の
            // 差が大きいという指摘を受け、段階的に広げている
            // （2026-08-03: horizontal 16→18, vertical 12→16→24）。
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
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
                      DefaultTextStyle.merge(style: titleStyle, child: title),
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
