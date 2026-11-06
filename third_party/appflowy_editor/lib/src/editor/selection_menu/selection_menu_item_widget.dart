import 'package:appflowy_editor/src/editor/selection_menu/selection_menu_service.dart';
import 'package:appflowy_editor/src/editor/selection_menu/selection_menu_widget.dart';
import 'package:appflowy_editor/src/editor_state.dart';
import 'package:flutter/material.dart';

/// ボタンを押したままメニューの項目へ指（マウス）をなぞって離すと選べるようにする為の窓口
/// （DaiDai側の追加）。押した元のウィジェットがポインターを握り続け、メニュー側には
/// イベントが届かない為、グローバル座標で項目の矩形を調べて代わりに通知する。
class SelectionMenuPointerTracker {
  SelectionMenuPointerTracker._();

  static final Set<_SelectionMenuItemWidgetState> _items = {};

  /// ポインターが動いた時。項目の上にある間、その項目を強調する。
  static void move(Offset globalPosition) {
    for (final item in _items) {
      item._setHover(item._contains(globalPosition));
    }
  }

  /// ポインターを離した時。項目の上なら選んだことにする（trueを返す）。
  static bool release(Offset globalPosition) {
    _SelectionMenuItemWidgetState? hit;
    for (final item in _items) {
      if (item._contains(globalPosition)) hit = item;
    }
    for (final item in _items.toList()) {
      item._setHover(false);
    }
    if (hit == null) return false;
    hit._invoke();
    return true;
  }

  /// 取り消し（強調を戻すだけ）。
  static void cancel() {
    for (final item in _items.toList()) {
      item._setHover(false);
    }
  }
}

class SelectionMenuItemWidget extends StatefulWidget {
  const SelectionMenuItemWidget({
    super.key,
    required this.editorState,
    required this.menuService,
    required this.item,
    required this.isSelected,
    required this.selectionMenuStyle,
    this.width = 140.0,
  });

  final EditorState editorState;
  final SelectionMenuService menuService;
  final SelectionMenuItem item;
  final double width;
  final bool isSelected;
  final SelectionMenuStyle selectionMenuStyle;

  @override
  State<SelectionMenuItemWidget> createState() =>
      _SelectionMenuItemWidgetState();
}

class _SelectionMenuItemWidgetState extends State<SelectionMenuItemWidget> {
  var _onHover = false;

  @override
  void initState() {
    super.initState();
    SelectionMenuPointerTracker._items.add(this);
  }

  @override
  void dispose() {
    SelectionMenuPointerTracker._items.remove(this);
    super.dispose();
  }

  bool _contains(Offset globalPosition) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return false;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    return rect.contains(globalPosition);
  }

  void _setHover(bool value) {
    if (!mounted || _onHover == value) return;
    setState(() => _onHover = value);
  }

  void _invoke() {
    widget.item.handler(widget.editorState, widget.menuService, context);
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.selectionMenuStyle;
    final isSelected = widget.isSelected || _onHover;
    return Container(
      padding: const EdgeInsets.fromLTRB(8.0, 5.0, 8.0, 5.0),
      child: SizedBox(
        width: widget.width,
        child: TextButton.icon(
          icon: widget.item.icon(
            widget.editorState,
            widget.isSelected || _onHover,
            widget.selectionMenuStyle,
          ),
          style: ButtonStyle(
            alignment: Alignment.centerLeft,
            overlayColor: WidgetStateProperty.all(
              style.selectionMenuItemSelectedColor,
            ),
            backgroundColor: widget.isSelected
                ? WidgetStateProperty.all(
                    style.selectionMenuItemSelectedColor,
                  )
                : WidgetStateProperty.all(Colors.transparent),
          ),
          label: widget.item.nameBuilder
                  ?.call(widget.item.name, style, isSelected) ??
              Text(
                widget.item.name,
                textAlign: TextAlign.left,
                style: TextStyle(
                  color: (widget.isSelected || _onHover)
                      ? style.selectionMenuItemSelectedTextColor
                      : style.selectionMenuItemTextColor,
                  fontSize: 12.0,
                ),
              ),
          onPressed: () {
            widget.item.handler(
              widget.editorState,
              widget.menuService,
              context,
            );
          },
          onHover: (value) {
            setState(() {
              _onHover = value;
            });
          },
        ),
      ),
    );
  }
}
