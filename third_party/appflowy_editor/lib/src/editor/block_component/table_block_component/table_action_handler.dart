import 'dart:math' as math;

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_editor/src/editor/block_component/table_block_component/table_action_menu.dart';
import 'package:flutter/material.dart';

class TableActionHandler extends StatefulWidget {
  const TableActionHandler({
    super.key,
    this.visible = false,
    this.height,
    required this.node,
    required this.editorState,
    required this.position,
    required this.alignment,
    required this.transform,
    required this.dir,
    this.menuBuilder,
    this.onHandleDragStart,
    this.onHandleDragUpdate,
    this.onHandleDragEnd,
    this.onHandleDragCancel,
  });

  final bool visible;
  final Node node;
  final EditorState editorState;
  final int position;
  final Alignment alignment;
  final Matrix4 transform;
  final double? height;
  final TableDirection dir;

  final TableBlockComponentMenuBuilder? menuBuilder;

  // 実際に行/列を並び替えるドラッグ操作（2026-09-28追加、ユーザー指示）。
  // `widget.menuBuilder`が指定されている場合はドラッグ非対応のまま
  // （既存の公開型`TableBlockComponentMenuBuilder`は変更しない）。
  final GestureDragStartCallback? onHandleDragStart;
  final GestureDragUpdateCallback? onHandleDragUpdate;
  final GestureDragEndCallback? onHandleDragEnd;
  final GestureDragCancelCallback? onHandleDragCancel;

  @override
  State<TableActionHandler> createState() => _TableActionHandlerState();
}

class _TableActionHandlerState extends State<TableActionHandler> {
  bool _visible = false;
  bool _menuShown = false;

  // ドラッグ中かどうか（2026-09-28追加、ユーザー指摘: ドロップ位置
  // インジケーターは出るのに離しても移動しない不具合への対応）。列/行の
  // 並び替えドラッグは、その性質上ほぼ必ずポインターが元のハンドル領域外へ
  // 移動する。`widget.visible`はそのハンドル自身のホバー状態に連動しており、
  // 領域外に出た瞬間`false`になる。`Visibility`は既定で`maintainState: false`
  // のため、`visible`が`false`になるとドラッグ中のGestureDetectorごと
  // サブツリーが破棄され、進行中の`DragGestureRecognizer`は`onEnd`を呼ばずに
  // 消えてしまう。ドラッグ中は元のホバー状態に関係なく表示を維持することで、
  // ドロップ（onEnd）が正しく発火するようにする。
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: widget.alignment,
      transform: widget.transform,
      height: widget.height,
      child: Visibility(
        visible: (widget.visible || _visible || _menuShown || _dragging) &&
            widget.editorState.editable,
        child: MouseRegion(
          onEnter: (_) => setState(() => _visible = true),
          onExit: (_) => setState(() => _visible = false),
          child: widget.menuBuilder != null
              ? widget.menuBuilder!(
                  widget.node,
                  widget.editorState,
                  widget.position,
                  widget.dir,
                  () => _menuShown = true,
                  () => setState(() => _menuShown = false),
                )
              : defaultMenuBuilder(
                  context,
                  widget.node,
                  widget.editorState,
                  widget.position,
                  widget.dir,
                  onHandleDragStart: (details) {
                    setState(() => _dragging = true);
                    widget.onHandleDragStart?.call(details);
                  },
                  onHandleDragUpdate: widget.onHandleDragUpdate,
                  onHandleDragEnd: (details) {
                    setState(() => _dragging = false);
                    widget.onHandleDragEnd?.call(details);
                  },
                  onHandleDragCancel: () {
                    setState(() => _dragging = false);
                    widget.onHandleDragCancel?.call();
                  },
                ),
        ),
      ),
    );
  }
}

Widget defaultMenuBuilder(
  BuildContext context,
  Node node,
  EditorState editorState,
  int position,
  TableDirection dir, {
  GestureDragStartCallback? onHandleDragStart,
  GestureDragUpdateCallback? onHandleDragUpdate,
  GestureDragEndCallback? onHandleDragEnd,
  GestureDragCancelCallback? onHandleDragCancel,
}) {
  // 添付画像を参考に、影付きの`Card`ではなく枠線の外に浮かぶ素のアイコンに
  // する（2026-09-27変更、ユーザー指示。CLAUDE.mdの「マテリアルに影を一切
  // 使わない」方針にも合わせた）。
  final icon = dir == TableDirection.col
      ? Transform.rotate(
          angle: math.pi / 2,
          child: TableDefaults.handlerIcon,
        )
      : TableDefaults.handlerIcon;

  return MouseRegion(
    cursor: SystemMouseCursors.click,
    child: GestureDetector(
      // 既定の`HitTestBehavior.deferToChild`だと、子（素のアイコン、~24px）
      // の範囲でしかヒットテストされず、ガターセル（28px）のほとんどで
      // クリックが素通りしてエディタ本体の選択ジェスチャーに奪われていた
      // （2026-09-28修正、ユーザー指摘。列幅リサイズの当たり領域
      // （table_view.dartの_buildResizeStrips）が既に`opaque`かつ実際の
      // 範囲全体をヒットテスト対象にしている、実証済みのパターンに揃えた）。
      behavior: HitTestBehavior.opaque,
      onTap: () => showActionMenu(
        context,
        node,
        editorState,
        position,
        dir,
      ),
      // Tap系とHorizontal/Vertical Drag系はFlutterが標準で1つの
      // GestureDetectorに併記できる（Pan/Scale系との組み合わせのみ非対応）。
      // 列は横方向、行は縦方向のドラッグとして並び替えを行う
      // （2026-09-28追加、ユーザー指示: ドラッグで実際に移動できるように）。
      onHorizontalDragStart:
          dir == TableDirection.col ? onHandleDragStart : null,
      onHorizontalDragUpdate:
          dir == TableDirection.col ? onHandleDragUpdate : null,
      onHorizontalDragEnd: dir == TableDirection.col ? onHandleDragEnd : null,
      onHorizontalDragCancel:
          dir == TableDirection.col ? onHandleDragCancel : null,
      onVerticalDragStart: dir == TableDirection.row ? onHandleDragStart : null,
      onVerticalDragUpdate:
          dir == TableDirection.row ? onHandleDragUpdate : null,
      onVerticalDragEnd: dir == TableDirection.row ? onHandleDragEnd : null,
      onVerticalDragCancel:
          dir == TableDirection.row ? onHandleDragCancel : null,
      child: SizedBox.expand(child: Center(child: icon)),
    ),
  );
}
