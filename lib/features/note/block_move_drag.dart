import 'dart:async';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// 画面に描画されている（`renderBox`を持つ）トップレベルのブロックの位置情報
/// （2026-10-04追加、ユーザー指示。目次・表のブロック移動ドラッグ用）。
class VisibleBlock {
  const VisibleBlock({
    required this.index,
    required this.top,
    required this.bottom,
  });

  /// `document.root.children`内のインデックス。
  final int index;

  /// グローバル座標のy。
  final double top;
  final double bottom;
}

/// ポインターのy座標から「どのブロックの前に挿入するか」（0〜ブロック数）を
/// 決める。各ブロックの上半分なら「そのブロックの前」、下半分なら次の
/// ブロックへ進み、全ブロックの下なら「最後のブロックの後ろ」。
int blockInsertIndex(List<VisibleBlock> blocks, double dy) {
  if (blocks.isEmpty) return 0;
  for (final block in blocks) {
    if (dy < (block.top + block.bottom) / 2) return block.index;
  }
  return blocks.last.index + 1;
}

/// `Transaction.moveNode`へ渡すパス（移動前の文書での挿入位置）。同じ位置へ
/// 戻す（実質移動しない）場合はnull。`moveNode`は「削除→挿入」の2操作だが、
/// `Transaction.add`が挿入パスを直前の削除に合わせて自動で補正する
/// （移動元より後ろなら1つ手前へ）ため、ここで補正してはいけない（二重に
/// ずれて1つ手前に入ってしまう）。
int? blockMoveTargetIndex(int from, int insertIndex) {
  return insertIndex == from || insertIndex == from + 1 ? null : insertIndex;
}

/// 移動後にそのブロックが実際に入るインデックス（移動後のカーソル位置用）。
int blockFinalIndex(int from, int insertIndex) {
  return insertIndex > from ? insertIndex - 1 : insertIndex;
}

/// 目次・表のブロック全体を、縦のドラッグで文書内の別の位置へ移動する
/// ハンドル（2026-10-04追加、ユーザー指示）。`appflowy_editor`にはブロックを
/// 動かすドラッグ機能が無いため、表の行/列並び替えと同様にポインター座標
/// から挿入位置を自前で計算し、ドラッグ中は挿入位置にガイドラインを表示、
/// 離した時に`Transaction.moveNode`で移動する。
///
/// 対象はルート直下のブロックのみ（リスト内の入れ子等は非対応で、その場合は
/// ハンドル自体を表示しない）。表示中でないブロック（`renderBox`が無い）は
/// 位置が取れないため挿入位置の候補から外れる。
class BlockMoveHandle extends StatefulWidget {
  const BlockMoveHandle({
    super.key,
    required this.node,
    required this.editorState,
    required this.color,
    this.tooltip,
    this.size = 28,
    this.selectAfterMove = false,
    this.child,
    this.onTap,
  });

  /// 動かさずに離した（タップした）時に呼ばれる。ドラッグ認識が押下の瞬間に
  /// ジェスチャーアリーナで勝つため、[child]内の`InkWell`等のタップは届かなく
  /// なる。タップ処理はこのコールバック（グローバル座標付き）で受ける。
  final void Function(Offset globalPosition)? onTap;

  /// 指定すると、アイコンの代わりにこのウィジェット全体をドラッグの掴み所に
  /// する（目次のヘッダー行全体など、掴める範囲を広げたい時に使う。
  /// [child]内のタップ等はそのまま動く）。
  final Widget? child;

  final Node node;
  final EditorState editorState;
  final Color color;
  final String? tooltip;
  final double size;

  /// 移動後に、移動したブロックへカーソルを置く（目次のようにブロック自体が
  /// 選択できる場合のみtrue。表はセル内にしかカーソルを置けないためfalse）。
  final bool selectAfterMove;

  @override
  State<BlockMoveHandle> createState() => _BlockMoveHandleState();
}

class _BlockMoveHandleState extends State<BlockMoveHandle> {
  OverlayEntry? _guide;
  Timer? _autoScrollTimer;
  double _pointerY = 0;
  int? _insertIndex;
  double? _guideY;
  bool _dragging = false;

  EditorState get _editorState => widget.editorState;

  bool get _isTopLevel => widget.node.parent == _editorState.document.root;

  @override
  void dispose() {
    _cleanup();
    super.dispose();
  }

  List<VisibleBlock> _visibleBlocks() {
    final blocks = <VisibleBlock>[];
    final children = _editorState.document.root.children.toList();
    for (var i = 0; i < children.length; i++) {
      final rect = children[i].rect;
      if (rect == Rect.zero) continue;
      blocks.add(VisibleBlock(index: i, top: rect.top, bottom: rect.bottom));
    }
    return blocks;
  }

  void _updateInsertPosition() {
    final blocks = _visibleBlocks();
    if (blocks.isEmpty) return;
    final index = blockInsertIndex(blocks, _pointerY);
    _insertIndex = index;
    final next = blocks.where((b) => b.index == index).firstOrNull;
    _guideY = next != null ? next.top : blocks.last.bottom;
    _guide?.markNeedsBuild();
  }

  void _showGuide() {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    final color = _editorState.editorStyle.cursorColor;
    _guide = OverlayEntry(
      builder: (context) {
        final box = _editorState.renderBox;
        final y = _guideY;
        if (box == null || y == null) return const SizedBox.shrink();
        final origin = box.localToGlobal(Offset.zero);
        return Positioned(
          left: origin.dx,
          top: y - 1,
          width: box.size.width,
          height: 2,
          child: IgnorePointer(child: ColoredBox(color: color)),
        );
      },
    );
    overlay.insert(_guide!);
  }

  void _startAutoScroll() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      final box = _editorState.renderBox;
      final scroll = _editorState.service.scrollService;
      if (box == null || scroll == null || !_dragging) return;
      final top = box.localToGlobal(Offset.zero).dy;
      final bottom = top + box.size.height;
      const edge = 56.0;
      const step = 10.0;
      double? target;
      if (_pointerY < top + edge) {
        target = scroll.dy - step;
      } else if (_pointerY > bottom - edge) {
        target = scroll.dy + step;
      }
      if (target == null) return;
      final clamped = target.clamp(
        scroll.minScrollExtent,
        scroll.maxScrollExtent,
      );
      if (clamped == scroll.dy) return;
      scroll.scrollTo(clamped, duration: Duration.zero);
      // スクロールで各ブロックの位置が変わるため、次フレームで再計算する。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_dragging) _updateInsertPosition();
      });
    });
  }

  void _onStart(Offset globalPosition) {
    if (!_isTopLevel) return;
    _dragging = true;
    _pointerY = globalPosition.dy;
    _updateInsertPosition();
    _showGuide();
    _startAutoScroll();
  }

  void _onUpdate(Offset globalPosition) {
    if (!_dragging) return;
    _pointerY = globalPosition.dy;
    _updateInsertPosition();
  }

  Future<void> _onEnd() async {
    final insertIndex = _insertIndex;
    final node = widget.node;
    _cleanup();
    if (insertIndex == null || node.parent == null) return;
    final from = node.path.first;
    final to = blockMoveTargetIndex(from, insertIndex);
    if (to == null) return;
    final transaction = _editorState.transaction..moveNode([to], node);
    if (widget.selectAfterMove) {
      transaction.afterSelection = Selection.collapsed(
        Position(path: [blockFinalIndex(from, to)]),
      );
    }
    await _editorState.apply(transaction);
  }

  void _cleanup() {
    _dragging = false;
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
    _guide?.remove();
    _guide = null;
    _insertIndex = null;
    _guideY = null;
  }

  @override
  Widget build(BuildContext context) {
    if (!_isTopLevel) return const SizedBox.shrink();
    Widget handle =
        widget.child ??
        SizedBox.square(
          dimension: widget.size,
          child: Center(
            child: Icon(
              Icons.drag_indicator,
              size: widget.size * 0.7,
              color: widget.color,
            ),
          ),
        );
    if (widget.tooltip != null) {
      handle = Tooltip(message: widget.tooltip!, child: handle);
    }
    return MouseRegion(
      cursor: SystemMouseCursors.grab,
      child: RawGestureDetector(
        behavior: HitTestBehavior.opaque,
        gestures: {
          _EagerBlockDragRecognizer:
              GestureRecognizerFactoryWithHandlers<_EagerBlockDragRecognizer>(
                _EagerBlockDragRecognizer.new,
                (recognizer) {
                  recognizer
                    ..onStart = _onStart
                    ..onUpdate = _onUpdate
                    ..onEnd = _onEnd
                    ..onCancel = _cleanup
                    ..onTap = widget.onTap;
                },
              ),
        },
        child: handle,
      ),
    );
  }
}

/// ポインター押下の瞬間にジェスチャーアリーナで勝つ（マウスの場合）ドラッグ
/// 認識器（2026-10-04追加、ユーザー指示）。エディタ全体のドラッグ選択
/// （`SelectionGestureDetector`、PCでは`ImmediateMultiDragGestureRecognizer`）
/// は押下の瞬間に勝利を宣言するため、通常の縦ドラッグ認識器（スロップを超えて
/// から勝つ）では負けて範囲選択になってしまう。タッチ・スタイラスは、
/// スクロールを奪わないようスロップを超えるまで勝利を宣言しない。
/// 動かさずに離した場合は[onTap]を呼ぶ。
class _EagerBlockDragRecognizer extends OneSequenceGestureRecognizer {
  void Function(Offset globalPosition)? onStart;
  void Function(Offset globalPosition)? onUpdate;
  VoidCallback? onEnd;
  VoidCallback? onCancel;
  void Function(Offset globalPosition)? onTap;

  static const double _slop = 6;

  int? _pointer;
  late Offset _downPosition;
  bool _dragging = false;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    if (_pointer != null) return;
    _pointer = event.pointer;
    _downPosition = event.position;
    _dragging = false;
    startTrackingPointer(event.pointer, event.transform);
    if (event.kind == PointerDeviceKind.mouse) {
      resolve(GestureDisposition.accepted);
    }
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event.pointer != _pointer) return;
    if (event is PointerMoveEvent) {
      if (_dragging) {
        onUpdate?.call(event.position);
      } else if ((event.position - _downPosition).distance > _slop) {
        resolve(GestureDisposition.accepted);
        _dragging = true;
        onStart?.call(event.position);
      }
    } else if (event is PointerUpEvent) {
      final wasDragging = _dragging;
      _finish();
      if (wasDragging) {
        onEnd?.call();
      } else {
        onTap?.call(event.position);
      }
    } else if (event is PointerCancelEvent) {
      final wasDragging = _dragging;
      _finish();
      if (wasDragging) onCancel?.call();
    }
  }

  void _finish() {
    final pointer = _pointer;
    _pointer = null;
    _dragging = false;
    if (pointer != null) stopTrackingPointer(pointer);
  }

  @override
  void rejectGesture(int pointer) {
    if (_dragging) onCancel?.call();
    _pointer = null;
    _dragging = false;
    super.rejectGesture(pointer);
  }

  @override
  void didStopTrackingLastPointer(int pointer) {}

  @override
  String get debugDescription => 'eagerBlockDrag';
}
