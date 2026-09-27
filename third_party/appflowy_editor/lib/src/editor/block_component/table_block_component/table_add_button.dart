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
  });

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
    return Container(
      padding: widget.padding,
      width: widget.width,
      height: widget.height,
      child: MouseRegion(
        onEnter: (_) => setState(() => _visible = true),
        onExit: (_) => setState(() => _visible = false),
        child: Center(
          child: Visibility(
            visible: _visible,
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
