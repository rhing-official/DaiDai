import 'package:flutter/gestures.dart' show kPrimaryButton;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_ui_style.dart';
import '../providers/app_ui_style_provider.dart';
import '../theme/block/block_theme.dart';
import '../theme/popup_surface_colors.dart';
import '../utils/drag_menu_geometry.dart';

/// [PressDragMenuButton]の項目1つ。
class PressDragMenuItem<T> {
  const PressDragMenuItem({
    required this.value,
    required this.icon,
    required this.label,
  });

  final T value;
  final IconData icon;
  final String label;
}

/// 押した瞬間にボタンの直下へメニューを開き、押したまま項目へなぞって離すとその項目を
/// 選べるボタン（2026-11-07、アルバムの「＋」。メッセージ入力欄の`AttachmentPopupButton`と
/// 同じ操作）。ほとんど動かさずに離した場合はメニューを開いたままにし、項目を
/// 個別にタップして選べる。メニューの見た目は`popupCardDecoration`1枚だけ
/// （`showMenu`のメニュー枠と重ねない。版画で枠が二重になっていた為）。
class PressDragMenuButton<T> extends ConsumerStatefulWidget {
  const PressDragMenuButton({
    required this.items,
    required this.onSelected,
    required this.child,
    this.enabled = true,
    this.menuWidth = 220,
    super.key,
  });

  final List<PressDragMenuItem<T>> items;
  final ValueChanged<T> onSelected;
  final Widget child;
  final bool enabled;
  final double menuWidth;

  @override
  ConsumerState<PressDragMenuButton<T>> createState() =>
      _PressDragMenuButtonState<T>();
}

class _PressDragMenuButtonState<T>
    extends ConsumerState<PressDragMenuButton<T>> {
  /// 離した位置がこの距離未満しか動いていなければ、単なるタップとして扱う。
  static const _tapSlop = 12.0;
  static const _hPad = 8.0;
  static const _vPad = 4.0;

  final _highlightIndex = ValueNotifier<int>(-1);
  OverlayEntry? _overlayEntry;
  DragMenuGeometry? _geometry;
  Offset? _downPosition;

  @override
  void dispose() {
    _removeOverlay();
    _highlightIndex.dispose();
    super.dispose();
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    _geometry = null;
  }

  void _select(T value) {
    _removeOverlay();
    widget.onSelected(value);
  }

  void _onPointerDown(PointerDownEvent event) {
    if (!widget.enabled || event.buttons != kPrimaryButton) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached) return;
    _removeOverlay();
    _downPosition = event.position;

    final overlayBox =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final screen = overlayBox.size;
    final brightness = Theme.of(context).brightness;
    final uiStyle = ref.read(appUiStyleProvider);
    final foreground = popupCardForeground(brightness, uiStyle);
    final accent = Theme.of(context).colorScheme.primary;
    final border = uiStyle == AppUiStyle.block ? BlockTheme.borderWidth : 1.0;
    final inset = border + _hPad;

    // ボタンの右端をそろえて、直下に開く（画面の端からはみ出さない）。
    final rect = box.localToGlobal(Offset.zero) & box.size;
    const screenPad = 8.0;
    final width = widget.menuWidth;
    final height =
        kDragMenuItemHeight * widget.items.length + (border + _vPad) * 2;
    final left = (rect.right - width).clamp(
      screenPad,
      (screen.width - width - screenPad).clamp(screenPad, double.infinity),
    );
    final top = (rect.bottom + 4).clamp(
      screenPad,
      (screen.height - height - screenPad).clamp(screenPad, double.infinity),
    );
    // 当たり判定は、項目が並ぶ内側の領域だけで取る。
    final geometry = DragMenuGeometry(
      left: left + inset,
      top: top + border + _vPad,
      width: width - inset * 2,
      itemCount: widget.items.length,
    );
    _geometry = geometry;
    _highlightIndex.value = -1;

    _overlayEntry = OverlayEntry(
      builder: (overlayContext) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _removeOverlay,
              child: const ColoredBox(color: Colors.transparent),
            ),
          ),
          Positioned(
            left: left,
            top: top,
            width: width,
            child: Container(
              decoration: popupCardDecoration(context, brightness, uiStyle),
              padding: EdgeInsets.symmetric(horizontal: _hPad, vertical: _vPad),
              child: Material(
                color: Colors.transparent,
                child: ValueListenableBuilder<int>(
                  valueListenable: _highlightIndex,
                  builder: (_, highlighted, _) => Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < widget.items.length; i++)
                        InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () => _select(widget.items[i].value),
                          child: Container(
                            height: kDragMenuItemHeight,
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              color: i == highlighted
                                  ? accent.withValues(alpha: 0.18)
                                  : Colors.transparent,
                            ),
                            child: Row(
                              children: [
                                Icon(widget.items[i].icon, color: foreground),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    widget.items[i].label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(color: foreground),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _onPointerMove(PointerMoveEvent event) {
    final geometry = _geometry;
    if (geometry == null) return;
    _highlightIndex.value = geometry.hitTest(event.position);
  }

  void _onPointerUp(PointerUpEvent event) {
    final down = _downPosition;
    _downPosition = null;
    final geometry = _geometry;
    if (geometry == null || down == null) return;
    // ほとんど動かずに離したら、メニューは開いたままにして個別のタップを待つ。
    if ((event.position - down).distance < _tapSlop) {
      _highlightIndex.value = -1;
      return;
    }
    final index = geometry.hitTest(event.position);
    _highlightIndex.value = -1;
    // なぞって項目の外で離した時は、開いたままにする。
    if (index < 0) return;
    _select(widget.items[index].value);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      onPointerCancel: (_) {
        _downPosition = null;
        _removeOverlay();
      },
      child: widget.child,
    );
  }
}
