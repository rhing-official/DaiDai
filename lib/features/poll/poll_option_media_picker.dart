import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../utils/drag_menu_geometry.dart';

/// [PollOptionMediaPickerButton]のドラッグ選択メニュー1項目。
enum _MediaChoice { image, video }

/// ほとんど動かさずに指が離れた場合は「押した瞬間に開くだけの単純な
/// タップ」とみなし、メニューを閉じずに開いたままにする（続けて項目を
/// 個別にタップして選べるようにするため）。`AttachmentPopupButton`
/// （`lib/features/chat/attachment_popup_button.dart`）と同じ値。
const double _tapSlop = 12.0;

/// 投票の選択肢に添付する画像・動画を選ぶボタン（2026-09-06追加、画像専用
/// だった選択肢添付を動画にも対応させる際に共通化）。押すと即座に（長押し
/// 不要）ボタンの右上に「画像」/「動画」の2択がポップアップし、指を
/// 触れたまま滑らせて選ぶ・または個別にタップして選ぶ、メッセージ入力欄の
/// ＋ボタン（`AttachmentPopupButton`）・メッセージ長押しメニュー
/// （`_MessageBubbleTapArea`、chat_screen.dart）と同じドラッグ選択UXにする
/// （2026-09-06変更、以前は`PopupMenuButton`の通常タップ選択だった）。
/// ジオメトリ計算は両者と共通の[DragMenuGeometry]を再利用する。
/// 選択済みならその場でプレビュー（画像はサムネイル、動画はアップロード前の
/// ためライブサムネイルを作らず動画アイコンのバッジ表示に留める）を表示する。
/// `poll_form_dialog.dart`（作成時）・`poll_detail_dialog.dart`（回答中の
/// 選択肢追加）の両方で使う。
class PollOptionMediaPickerButton extends StatefulWidget {
  const PollOptionMediaPickerButton({
    required this.strings,
    required this.mediaBytes,
    required this.mediaType,
    required this.onPick,
    this.enabled = true,
    super.key,
  });

  final Strings strings;
  final Uint8List? mediaBytes;

  /// 'image' | 'video' | null（未選択）。
  final String? mediaType;
  final void Function(bool video) onPick;
  final bool enabled;

  static const double _size = 56;

  @override
  State<PollOptionMediaPickerButton> createState() =>
      _PollOptionMediaPickerButtonState();
}

class _PollOptionMediaPickerButtonState
    extends State<PollOptionMediaPickerButton> {
  final _highlightIndex = ValueNotifier<int>(-1);
  OverlayEntry? _overlayEntry;
  DragMenuGeometry? _geometry;
  List<({_MediaChoice choice, String label})> _items = const [];
  Offset? _pointerDownPosition;

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

  List<({_MediaChoice choice, String label})> _buildItems() {
    return [
      (choice: _MediaChoice.image, label: widget.strings.chatAttachImage),
      (choice: _MediaChoice.video, label: widget.strings.chatAttachVideo),
    ];
  }

  void _handleSelection(_MediaChoice choice) {
    widget.onPick(choice == _MediaChoice.video);
  }

  void _onPointerDown(PointerDownEvent event) {
    if (!widget.enabled) return;
    _pointerDownPosition = event.position;
    final items = _buildItems();
    final colorScheme = Theme.of(context).colorScheme;
    final overlayBox =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final screenSize = overlayBox.size;
    final textStyle = Theme.of(context).textTheme.bodyLarge!;
    final textScaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);

    const hPad = 16.0;
    var maxLabelWidth = 0.0;
    for (final item in items) {
      final painter = TextPainter(
        text: TextSpan(text: item.label, style: textStyle),
        textDirection: direction,
        textScaler: textScaler,
      )..layout();
      if (painter.width > maxLabelWidth) maxLabelWidth = painter.width;
    }
    final menuWidth = (maxLabelWidth + hPad * 2).clamp(72.0, 160.0);
    final menuHeight = kDragMenuItemHeight * items.length;

    // ボタン自身（Listenerの子＝このボタンの矩形と一致）の右上角を基準に、
    // その角がメニューの左下角に来るように表示する（要望どおり「ボタンの
    // 右上」に2択を出す。押した指の座標基準の`AttachmentPopupButton`とは
    // 異なり、56x56の固定ボタン自体を基準にする）。
    final buttonBox = context.findRenderObject()! as RenderBox;
    final topRight = buttonBox.localToGlobal(Offset(buttonBox.size.width, 0));

    const screenPad = 8.0;
    final left = topRight.dx.clamp(
      screenPad,
      screenSize.width - menuWidth - screenPad,
    );
    final top = (topRight.dy - menuHeight).clamp(
      screenPad,
      screenSize.height - menuHeight - screenPad,
    );

    final geometry = DragMenuGeometry(
      left: left,
      top: top,
      width: menuWidth,
      itemCount: items.length,
    );
    _items = items;
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
            left: geometry.left,
            top: geometry.top,
            width: geometry.width,
            height: geometry.height,
            child: Material(
              color: colorScheme.surfaceContainer,
              elevation: 3,
              shadowColor: colorScheme.shadow,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(4)),
              ),
              child: ValueListenableBuilder<int>(
                valueListenable: _highlightIndex,
                builder: (_, highlighted, _) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < items.length; i++)
                      InkWell(
                        onTap: () {
                          _removeOverlay();
                          _handleSelection(items[i].choice);
                        },
                        child: Container(
                          height: kDragMenuItemHeight,
                          alignment: AlignmentDirectional.centerStart,
                          padding: const EdgeInsets.symmetric(horizontal: hPad),
                          color: i == highlighted
                              ? colorScheme.primary.withValues(alpha: 0.12)
                              : Colors.transparent,
                          child: Text(
                            items[i].label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textStyle.copyWith(
                              color: i == highlighted
                                  ? colorScheme.primary
                                  : null,
                            ),
                          ),
                        ),
                      ),
                  ],
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
    final downPosition = _pointerDownPosition;
    _pointerDownPosition = null;
    if (downPosition != null &&
        (event.position - downPosition).distance < _tapSlop) {
      _highlightIndex.value = -1;
      return;
    }

    final geometry = _geometry;
    final items = _items;
    _removeOverlay();
    if (geometry == null) return;
    final index = geometry.hitTest(event.position);
    if (index < 0) return;
    _highlightIndex.value = -1;
    _handleSelection(items[index].choice);
  }

  @override
  Widget build(BuildContext context) {
    final mediaBytes = widget.mediaBytes;
    Widget preview;
    if (widget.mediaType == 'image' && mediaBytes != null) {
      preview = ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.memory(
          mediaBytes,
          width: PollOptionMediaPickerButton._size,
          height: PollOptionMediaPickerButton._size,
          fit: BoxFit.cover,
        ),
      );
    } else if (widget.mediaType == 'video') {
      preview = Container(
        width: PollOptionMediaPickerButton._size,
        height: PollOptionMediaPickerButton._size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
        child: const Icon(Icons.videocam),
      );
    } else {
      preview = SizedBox(
        width: PollOptionMediaPickerButton._size,
        height: PollOptionMediaPickerButton._size,
        child: const Icon(Icons.add_photo_alternate_outlined),
      );
    }

    return Listener(
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      child: preview,
    );
  }
}
