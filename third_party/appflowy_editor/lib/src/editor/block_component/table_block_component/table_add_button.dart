import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_editor/src/editor/block_component/table_block_component/util.dart';
import 'package:flutter/material.dart';

class TableActionButton extends StatefulWidget {
  const TableActionButton({
    super.key,
    required this.width,
    required this.height,
    required this.padding,
    required this.onPressed,
    required this.icon,
    required this.borderColor,
    this.table,
    this.editorState,
  });

  // DaiDai patch（2026-10-17）: タッチ主体の端末で、この表の中に選択がある間は
  // ホバーなしで常に表示するための参照（nullなら従来どおりホバーのみ）。
  final Node? table;
  final EditorState? editorState;

  final double width, height;
  final EdgeInsetsGeometry padding;
  final Function onPressed;
  final Widget icon;

  // 影付きの`Card`の代わりに、細い枠線で囲む見た目にするための色
  // （2026-09-27変更、ユーザー指示。CLAUDE.mdの「マテリアルに影を一切
  // 使わない」方針にも合わせた）。
  final Color borderColor;

  @override
  State<TableActionButton> createState() => _TableActionButtonState();
}

class _TableActionButtonState extends State<TableActionButton> {
  bool _visible = false;

  @override
  Widget build(BuildContext context) {
    final table = widget.table;
    final editorState = widget.editorState;
    if (table == null || editorState == null) {
      return _buildBody(context, false);
    }
    return TableTouchActiveBuilder(
      table: table,
      editorState: editorState,
      builder: _buildBody,
    );
  }

  Widget _buildBody(BuildContext context, bool touchActive) {
    return Container(
      padding: widget.padding,
      width: widget.width,
      height: widget.height,
      child: MouseRegion(
        onEnter: (_) => setState(() => _visible = true),
        onExit: (_) => setState(() => _visible = false),
        child: Center(
          child: Visibility(
            visible: _visible || touchActive,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () => widget.onPressed(),
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    border: Border.all(color: widget.borderColor),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: widget.icon,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
