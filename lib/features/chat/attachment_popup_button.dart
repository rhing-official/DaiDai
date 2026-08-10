import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../l10n/strings.dart';
import '../../utils/drag_menu_geometry.dart';
import '../../widgets/gekiga/gekiga_icon_badge.dart';
import 'camera_capture_screen.dart';

/// 選択済みの添付データ（`ChatScreen.onSendAttachment`に渡す）。
class PickedAttachment {
  const PickedAttachment({
    required this.bytes,
    required this.fileName,
    required this.contentType,
  });

  final Uint8List bytes;
  final String fileName;

  /// file | image | video
  final String contentType;
}

enum _AttachmentMenuItem { file, image, video, capture }

/// ポインター位置がこの距離未満しか動かないまま指が離れた場合、
/// 「押した瞬間にポップアップを開くだけの単純なタップ」とみなし、
/// メニューを閉じずに開いたままにする（続けて項目を個別にタップして
/// 選べるようにするため）。これを超えて動いた場合のみ、長押しメニューと
/// 同じ「指を離さず滑らせて選ぶ」ドラッグ選択として扱う。
const double _tapSlop = 12.0;

/// メッセージ入力欄の＋ボタン。押すと即座に（長押し不要）すぐ上にポップアップが
/// 開き、「ファイル・画像・動画・撮影」の4項目から選べる（技術仕様書5.6参照、
/// 2026-08-10追加）。項目選択は、メッセージの長押しメニュー
/// （`_MessageBubbleTapArea`、chat_screen.dart）と同じ「指を触れたまま
/// スワイプして選ぶ」ドラッグ選択にも対応する（[DragMenuGeometry]を共有）。
/// メニューが開いた状態で項目を個別にタップして選ぶ通常の操作にも対応する
/// （各項目自体が[InkWell]を持つため）。
class AttachmentPopupButton extends StatefulWidget {
  const AttachmentPopupButton({
    required this.strings,
    required this.isGekiga,
    required this.onPicked,
    super.key,
  });

  final Strings strings;

  /// 劇画スタイル選択時、他のモノクロボックス意匠（寄合追加ボタン等）と
  /// 統一感を持たせるため、アイコンを[GekigaIconBadge]に差し替える
  /// （2026-08-10追加）。ドラッグ選択のジオメトリ計算・ポップアップメニュー
  /// 自体の見た目はスタイル分岐しない。
  final bool isGekiga;

  final void Function(PickedAttachment attachment) onPicked;

  @override
  State<AttachmentPopupButton> createState() => _AttachmentPopupButtonState();
}

class _AttachmentPopupButtonState extends State<AttachmentPopupButton> {
  final _highlightIndex = ValueNotifier<int>(-1);
  OverlayEntry? _overlayEntry;
  DragMenuGeometry? _geometry;
  List<({_AttachmentMenuItem item, String label})> _items = const [];
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

  List<({_AttachmentMenuItem item, String label})> _buildItems(
    Strings strings,
  ) {
    return [
      (item: _AttachmentMenuItem.file, label: strings.chatAttachFile),
      (item: _AttachmentMenuItem.image, label: strings.chatAttachImage),
      (item: _AttachmentMenuItem.video, label: strings.chatAttachVideo),
      (item: _AttachmentMenuItem.capture, label: strings.chatAttachCapture),
    ];
  }

  Future<void> _handleSelection(_AttachmentMenuItem? item) async {
    if (!mounted || item == null) return;
    switch (item) {
      case _AttachmentMenuItem.file:
        await _pickFile();
      case _AttachmentMenuItem.image:
        await _pickImage();
      case _AttachmentMenuItem.video:
        await _pickVideo();
      case _AttachmentMenuItem.capture:
        await _openCamera();
    }
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(withData: true);
    final file = result?.files.single;
    final bytes = file?.bytes;
    if (file == null || bytes == null) return;
    widget.onPicked(
      PickedAttachment(bytes: bytes, fileName: file.name, contentType: 'file'),
    );
  }

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    widget.onPicked(
      PickedAttachment(
        bytes: bytes,
        fileName: picked.name,
        contentType: 'image',
      ),
    );
  }

  Future<void> _pickVideo() async {
    final picked = await ImagePicker().pickVideo(source: ImageSource.gallery);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    widget.onPicked(
      PickedAttachment(
        bytes: bytes,
        fileName: picked.name,
        contentType: 'video',
      ),
    );
  }

  Future<void> _openCamera() async {
    if (!mounted) return;
    final captured = await Navigator.of(context).push<CapturedMedia>(
      MaterialPageRoute(builder: (_) => const CameraCaptureScreen()),
    );
    if (captured == null) return;
    widget.onPicked(
      PickedAttachment(
        bytes: captured.bytes,
        fileName: captured.fileName,
        contentType: captured.isVideo ? 'video' : 'image',
      ),
    );
  }

  void _onPointerDown(PointerDownEvent event) {
    // メッセージ入力欄で文字入力中にこのボタンを押した場合、既に開いている
    // ソフトウェアキーボードをまず閉じる。開いたままだとレイアウトが
    // 変化し、この直後に計算するポップアップの表示位置がズレてしまう
    // （2026-08-10追加、＋ボタンでキーボードが開いてポップアップの位置が
    // おかしくなる不具合の対策）。
    FocusScope.of(context).unfocus();
    _pointerDownPosition = event.position;
    final items = _buildItems(widget.strings);
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
    final menuWidth = (maxLabelWidth + hPad * 2).clamp(140.0, 280.0);
    final menuHeight = kDragMenuItemHeight * items.length;

    // ポップアップは＋ボタンのすぐ上に開く（技術仕様書5.6参照）。
    const screenPad = 8.0;
    final left = event.position.dx.clamp(
      screenPad,
      screenSize.width - menuWidth - screenPad,
    );
    final top = (event.position.dy - menuHeight - 8).clamp(
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
                          _handleSelection(items[i].item);
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
    // ほとんど動かずに指が離れた場合は「押した瞬間に開くだけの単純な
    // タップ」とみなし、メニューを閉じずに開いたままにする。続けて項目を
    // 個別にタップして選べるようにするため（各項目のInkWellが処理する）。
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
    _handleSelection(items[index].item);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      // 送信ボタン（chat_screen.dartのIcons.send）とタップ領域の大きさを
      // 揃えるためのpadding。
      child: widget.isGekiga
          ? const Padding(
              padding: EdgeInsets.all(6),
              child: GekigaIconBadge(icon: Icons.add, size: 32),
            )
          : Padding(
              padding: const EdgeInsets.all(12),
              child: Icon(
                Icons.add_circle_outline,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
    );
  }
}
