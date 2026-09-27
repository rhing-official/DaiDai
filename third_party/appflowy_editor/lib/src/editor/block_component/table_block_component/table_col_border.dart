import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// 罫線そのものは見た目のみを担当する（2026-09-27変更、ユーザー指示）。
// 以前はここに列幅リサイズ用のホバー・ドラッグ判定を直接持たせていたが、
// 小さい`SizedBox`の中で`Positioned`をはみ出させても実際には当たり判定が
// 広がらない（Flutterの`RenderBox.hitTest`は祖先自身の`size.contains`が
// 真でない限り子のヒットテストへ進まない）ため、当たり判定は表全体サイズの
// Stackを持つ`table_view.dart`側へ完全に移設した。この罫線ウィジェットは
// レイアウト上の幅（`config.borderWidth`）を変えず、ハイライト色の表示のみ行う。
class TableColBorder extends StatelessWidget {
  const TableColBorder({
    super.key,
    required this.tableNode,
    required this.colIdx,
    required this.resizable,
    required this.borderColor,
    required this.borderHoverColor,
    this.highlighted = false,
  });

  final bool resizable;
  final int colIdx;
  final TableNode tableNode;

  final Color borderColor;
  final Color borderHoverColor;

  // 列幅リサイズの当たり領域（`table_view.dart`）がホバー・ドラッグ中の間、
  // 色をハイライトさせるためのフラグ。
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: tableNode.config.borderWidth,
      height: context.select(
        (Node n) => n.attributes[TableBlockKeys.colsHeight],
      ),
      color: resizable && highlighted ? borderHoverColor : borderColor,
    );
  }
}
