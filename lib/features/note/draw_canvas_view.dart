import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';
import '../../models/app_user.dart';
import '../../models/note_stroke.dart';
import '../../providers/repository_providers.dart';
import '../../utils/color_hex.dart';
import '../../utils/note_export.dart';
import '../../widgets/dialog_keyboard_shortcuts.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/honeycomb_color_picker.dart';
import '../../widgets/copy_link_row.dart';

enum _DrawTool { pen, eraser, pan }

/// ズーム倍率の範囲（2026-10-10追加。縮小側は2026-11-05に実質無制限へ変更）。
/// 倍率が0や負になると描画が壊れる為、下限は極小の正の値にとどめる。
const kDrawMinZoom = 0.001;
const kDrawMaxZoom = 5.0;

/// ツールバーの＋／−ボタン1回あたりの倍率。
const kDrawZoomStep = 1.25;

double clampDrawZoom(double zoom) =>
    zoom.clamp(kDrawMinZoom, kDrawMaxZoom).toDouble();

/// 焦点（ビューポート内の座標）[focal]が動かないように、倍率を[oldZoom]から
/// [newZoom]へ変えた時のスクロール量を返す。コンテンツ上の同じ点が焦点の下に
/// 残るようにする（ピンチ・Ctrl＋ホイールのズーム用）。
double zoomedScrollOffset({
  required double offset,
  required double focal,
  required double oldZoom,
  required double newZoom,
}) => (offset + focal) * newZoom / oldZoom - focal;

/// ドローノートのキャンバスとツールバー（2026-10-04追加）。
///
/// 線は`notes/{noteId}/strokes`に1線1ドキュメントで保存し、他の参加者が描いた
/// 線もライブで反映される（[NoteRepository.watchStrokes]）。消しゴムは線単位で
/// 削除、取り消しは自分が最後に描いた線の削除、やり直しは直前に取り消した線の
/// 再追加。論理幅は[NoteStroke.canvasWidth]固定で画面幅に合わせて拡縮し、
/// 高さは描画範囲に応じて縦に伸びる（縦スクロール、「移動」ツールで操作）。
/// キャンバスの背景は常に白（PNG書き出しと同じ見た目にする為）。
class DrawCanvasView extends ConsumerStatefulWidget {
  const DrawCanvasView({
    required this.isDm,
    required this.conversationId,
    required this.roomId,
    required this.noteId,
    required this.currentUser,
    required this.foreground,
    required this.background,
    super.key,
  });

  final bool isDm;
  final String conversationId;
  final String roomId;
  final String noteId;
  final AppUser currentUser;

  /// ツールバーのアイコン・文字色と地の色（ノート画面の配色に合わせる）。
  final Color foreground;
  final Color background;

  @override
  ConsumerState<DrawCanvasView> createState() => _DrawCanvasViewState();
}

class _DrawCanvasViewState extends ConsumerState<DrawCanvasView> {
  /// 線の外接矩形の外側に常に確保する余白（論理座標）。縦横とも、描いた範囲の外へさらに
  /// この分だけ動ける（iOSのメモのように、描き進めるほど領域が広がる、2026-11-05）。
  static const _pad = 1000.0;

  /// 何も描いていない時の基準の領域（論理座標、左上が原点）。
  static const _baseRect = Rect.fromLTWH(
    0,
    0,
    NoteStroke.canvasWidth,
    NoteStroke.canvasWidth,
  );
  static const _maxPointsPerStroke = 4000;
  static const _presetColors = <int>[
    0xFF000000,
    0xFFE53935,
    0xFFEE7800,
    0xFFFDD835,
    0xFF43A047,
    0xFF1E88E5,
    0xFF8E24AA,
    0xFF6D4C41,
  ];

  StreamSubscription<List<NoteStroke>>? _sub;
  List<NoteStroke> _strokes = const [];
  final _scrollController = ScrollController();

  /// 拡大で幅が画面幅を超えた時の横スクロール。`NeverScrollableScrollPhysics`で、
  /// 「移動」ツールのドラッグ・トラックパッドの横スクロール・ピンチの焦点補正だけが
  /// `jumpTo`で動かす（2026-10-10追加）。
  final _hController = ScrollController();

  /// ズーム倍率（1.0＝画面幅フィット、2026-10-10追加、保存・同期しない）。
  double _zoom = 1.0;

  /// ビューポート（スクロール領域）のキーと大きさ。ピンチ・Ctrl＋ホイールの
  /// 焦点（グローバル座標）をビューポート内の座標へ変換するのに使う。
  final _viewportKey = GlobalKey();
  Size _viewportSize = Size.zero;

  /// 押されているポインタ（グローバル座標）。2本になったらピンチを始める。
  final _pointers = <int, Offset>{};
  bool _pinching = false;
  double _pinchStartDistance = 1;
  double _pinchStartZoom = 1;
  double _panZoomStartZoom = 1;

  _DrawTool _tool = _DrawTool.pen;
  int _color = 0xFF000000;
  double _width = 5;

  /// 描画中の線（論理座標）。確定するまでFirestoreには書かない。
  final _currentPoints = ValueNotifier<List<Offset>>(const []);
  int? _drawingPointer;

  /// 自分が描いた線のid（取り消し用、新しい順に末尾）と、取り消した線（やり直し用）。
  final _myStrokeIds = <String>[];
  final _redoStack = <NoteStroke>[];
  final _erasedIds = <String>{};

  @override
  void initState() {
    super.initState();
    _sub = ref
        .read(noteRepositoryProvider)
        .watchStrokes(
          isDm: widget.isDm,
          conversationId: widget.conversationId,
          roomId: widget.roomId,
          noteId: widget.noteId,
        )
        .listen((strokes) {
          if (!mounted) return;
          setState(() {
            _strokes = strokes;
            final ids = {for (final s in strokes) s.strokeId};
            _erasedIds.removeWhere((id) => !ids.contains(id));
            _myStrokeIds.removeWhere((id) => !ids.contains(id));
          });
        });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _scrollController.dispose();
    _hController.dispose();
    _currentPoints.dispose();
    super.dispose();
  }

  List<NoteStroke> get _visibleStrokes => [
    for (final s in _strokes)
      if (!_erasedIds.contains(s.strokeId)) s,
  ];

  /// スクロール出来る全領域（論理座標）。基準の領域と全ての線の外接矩形を含み、外側に
  /// [_pad]の余白を足したもの。左・上へ描き進むと左上（原点）が負の側へ広がる。
  Rect _contentBounds() {
    var rect = _baseRect;
    for (final s in _strokes) {
      if (s.pointCount > 0) rect = rect.expandToInclude(s.bounds);
    }
    return rect.inflate(_pad);
  }

  /// 前回のレイアウトでの領域の左上（論理座標）。変わったら、見ている位置が動かない
  /// ようにスクロール量を補正する。nullなら初回（原点が画面の左上に来る位置へ送る）。
  Offset? _lastOrigin;

  void _syncScrollToOrigin(Offset origin, double scale) {
    final last = _lastOrigin;
    _lastOrigin = origin;
    if (last == origin) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (last == null) {
        // 初回: 論理座標の原点（0,0）が画面の左上に来る位置へ。
        _jumpClamped(_hController, -origin.dx * scale);
        _jumpClamped(_scrollController, -origin.dy * scale);
        return;
      }
      if (_hController.hasClients) {
        _jumpClamped(
          _hController,
          _hController.offset + (last.dx - origin.dx) * scale,
        );
      }
      if (_scrollController.hasClients) {
        _jumpClamped(
          _scrollController,
          _scrollController.offset + (last.dy - origin.dy) * scale,
        );
      }
    });
  }

  Offset _toLogical(Offset local, double scale, Offset origin) =>
      local / scale + origin;

  /// グローバル座標をビューポート内の座標へ変換する。
  Offset _toViewport(Offset global) {
    final box = _viewportKey.currentContext?.findRenderObject();
    return box is RenderBox ? box.globalToLocal(global) : global;
  }

  void _jumpClamped(ScrollController controller, double target) {
    if (!controller.hasClients) return;
    final position = controller.position;
    controller.jumpTo(
      target.clamp(position.minScrollExtent, position.maxScrollExtent),
    );
  }

  /// 倍率を[target]へ変える。ビューポート内の座標[focal]の下のコンテンツが
  /// 動かないよう、レイアウト更新後のフレームでスクロール量を補正する。
  void _applyZoom(double target, Offset focal) {
    final newZoom = clampDrawZoom(target);
    final oldZoom = _zoom;
    if ((newZoom - oldZoom).abs() < 0.0001) return;
    final h = _hController.hasClients ? _hController.offset : 0.0;
    final v = _scrollController.hasClients ? _scrollController.offset : 0.0;
    final newH = zoomedScrollOffset(
      offset: h,
      focal: focal.dx,
      oldZoom: oldZoom,
      newZoom: newZoom,
    );
    final newV = zoomedScrollOffset(
      offset: v,
      focal: focal.dy,
      oldZoom: oldZoom,
      newZoom: newZoom,
    );
    setState(() => _zoom = newZoom);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _jumpClamped(_hController, newH);
      _jumpClamped(_scrollController, newV);
    });
  }

  /// ツールバーの＋／−（ビューポートの中心を焦点にする）。
  void _zoomByStep(double factor) => _applyZoom(
    _zoom * factor,
    Offset(_viewportSize.width / 2, _viewportSize.height / 2),
  );

  void _startPinch() {
    // 描画中の線は破棄する（ピンチの1本目の動きを線として残さない）。
    _currentPoints.value = const [];
    _drawingPointer = null;
    final points = _pointers.values.take(2).toList();
    _pinchStartDistance = math.max((points[0] - points[1]).distance, 1);
    _pinchStartZoom = _zoom;
    setState(() => _pinching = true);
  }

  void _updatePinch() {
    final points = _pointers.values.take(2).toList();
    if (points.length < 2) return;
    final distance = (points[0] - points[1]).distance;
    _applyZoom(
      _pinchStartZoom * distance / _pinchStartDistance,
      _toViewport((points[0] + points[1]) / 2),
    );
  }

  /// ビューポート全体で受ける、ピンチ・「移動」ツールの横ドラッグ用のポインタ
  /// 追跡（ペン/消しゴムの描画は内側の`Listener`が受ける）。
  void _onViewportPointerDown(PointerDownEvent event) {
    _pointers[event.pointer] = event.position;
    if (_pointers.length == 2) _startPinch();
  }

  void _onViewportPointerMove(PointerMoveEvent event) {
    if (!_pointers.containsKey(event.pointer)) return;
    _pointers[event.pointer] = event.position;
    if (_pinching) {
      _updatePinch();
    } else if (_tool == _DrawTool.pan && _pointers.length == 1) {
      // 縦横とも自前で動かす（2026-11-05）。標準のドラッグスクロールは、マウスでは
      // 効かない（`ScrollBehavior.dragDevices`にマウスが含まれない）ため、縦も含めて
      // ここで`jumpTo`する。そのため縦の`SingleChildScrollView`は常にユーザー操作を
      // 受け付けない（タッチで二重に動かないように）。
      if (_hController.hasClients) {
        _jumpClamped(_hController, _hController.offset - event.delta.dx);
      }
      if (_scrollController.hasClients) {
        _jumpClamped(
          _scrollController,
          _scrollController.offset - event.delta.dy,
        );
      }
    }
  }

  void _onViewportPointerEnd(PointerEvent event) {
    _pointers.remove(event.pointer);
    // 全ての指が離れるまでは描画を再開しない。
    if (_pointers.isEmpty && _pinching) setState(() => _pinching = false);
  }

  void _onViewportSignal(PointerSignalEvent signal) {
    final focal = _toViewport(signal.position);
    if (signal is PointerScaleEvent) {
      // Webでは、トラックパッドのピンチ・Ctrl＋ホイールがこの形で届く。
      _applyZoom(_zoom * signal.scale, focal);
    } else if (signal is PointerScrollEvent) {
      final keyboard = HardwareKeyboard.instance;
      // マウスホイールで拡大・縮小する（2026-11-05、ユーザー指示。以前はCtrl／Cmd＋
      // ホイールだけが拡縮で、ホイールだけは縦スクロールだった）。ホイールの1目盛りで
      // 約2割変わる。スクロールはShift＋ホイール（縦）に移した。
      if (!keyboard.isShiftPressed) {
        _applyZoom(_zoom * math.exp(-signal.scrollDelta.dy / 500), focal);
        return;
      }
      // Shift＋ホイール: ペン/消しゴム中でもスクロール出来る。ブラウザはShift＋ホイールを
      // 横方向（dx）として渡すことがある為、縦・横どちらの値でも縦スクロールに使う。
      final dy = signal.scrollDelta.dy != 0
          ? signal.scrollDelta.dy
          : signal.scrollDelta.dx;
      if (_scrollController.hasClients) {
        _jumpClamped(_scrollController, _scrollController.offset + dy);
      }
    }
  }

  void _onPanZoomStart(PointerPanZoomStartEvent event) {
    _panZoomStartZoom = _zoom;
  }

  void _onPanZoomUpdate(PointerPanZoomUpdateEvent event) {
    // ネイティブ（デスクトップ）のトラックパッドのピンチ。
    _applyZoom(_panZoomStartZoom * event.scale, _toViewport(event.position));
  }

  void _onPointerDown(PointerDownEvent event, double scale, Offset origin) {
    if (_pinching || _pointers.length >= 2) return;
    if (_tool == _DrawTool.pan || _drawingPointer != null) return;
    _drawingPointer = event.pointer;
    final point = _toLogical(event.localPosition, scale, origin);
    if (_tool == _DrawTool.pen) {
      _currentPoints.value = [point];
    } else {
      _erase(point);
    }
  }

  void _onPointerMove(PointerMoveEvent event, double scale, Offset origin) {
    if (_pinching || event.pointer != _drawingPointer) return;
    final point = _toLogical(event.localPosition, scale, origin);
    if (_tool == _DrawTool.pen) {
      final points = _currentPoints.value;
      if (points.isEmpty || points.length >= _maxPointsPerStroke) return;
      // 近すぎる点は間引く（保存サイズと再描画コストの削減）。
      if ((points.last - point).distance < 1.5) return;
      _currentPoints.value = [...points, point];
    } else {
      _erase(point);
    }
  }

  void _onPointerEnd(PointerEvent event) {
    if (_pinching || event.pointer != _drawingPointer) return;
    _drawingPointer = null;
    if (_tool == _DrawTool.pen) _commitCurrentStroke();
  }

  void _erase(Offset logicalPoint) {
    final hit = <String>[];
    for (final s in _visibleStrokes) {
      if (!s.bounds.inflate(12).contains(logicalPoint)) continue;
      if (s.hitTest(logicalPoint, 10)) hit.add(s.strokeId);
    }
    if (hit.isEmpty) return;
    setState(() => _erasedIds.addAll(hit));
    _deleteStrokes(hit);
  }

  Future<void> _deleteStrokes(List<String> ids) {
    return ref
        .read(noteRepositoryProvider)
        .deleteStrokes(
          isDm: widget.isDm,
          conversationId: widget.conversationId,
          roomId: widget.roomId,
          noteId: widget.noteId,
          strokeIds: ids,
        );
  }

  Future<void> _commitCurrentStroke() async {
    final points = _currentPoints.value;
    _currentPoints.value = const [];
    if (points.isEmpty) return;
    final stroke = NoteStroke(
      strokeId: '',
      points: [
        for (final p in points) ...[_round(p.dx), _round(p.dy)],
      ],
      color: _color,
      width: _width,
      authorId: widget.currentUser.userId,
    );
    _redoStack.clear();
    final id = await _addStroke(stroke);
    if (id != null && mounted) setState(() => _myStrokeIds.add(id));
  }

  double _round(double v) => (v * 10).roundToDouble() / 10;

  Future<String?> _addStroke(NoteStroke stroke) async {
    try {
      return await ref
          .read(noteRepositoryProvider)
          .addStroke(
            isDm: widget.isDm,
            conversationId: widget.conversationId,
            roomId: widget.roomId,
            noteId: widget.noteId,
            stroke: stroke,
          );
    } catch (e) {
      debugPrint('[note-draw] addStroke failed: $e');
      return null;
    }
  }

  Future<void> _undo() async {
    if (_myStrokeIds.isEmpty) return;
    final id = _myStrokeIds.removeLast();
    final stroke = _strokes.where((s) => s.strokeId == id).firstOrNull;
    if (stroke != null) _redoStack.add(stroke);
    setState(() => _erasedIds.add(id));
    await _deleteStrokes([id]);
  }

  Future<void> _redo() async {
    if (_redoStack.isEmpty) return;
    final stroke = _redoStack.removeLast();
    setState(() {});
    final id = await _addStroke(
      NoteStroke(
        strokeId: '',
        points: stroke.points,
        color: stroke.color,
        width: stroke.width,
        authorId: widget.currentUser.userId,
      ),
    );
    if (id != null && mounted) setState(() => _myStrokeIds.add(id));
  }

  Future<void> _clearAll(Strings strings) async {
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (context) => KeyboardAlertDialog(
        content: Text(strings.noteDrawClearConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(strings.noteDrawClearConfirmButton),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final ids = [for (final s in _strokes) s.strokeId];
    setState(() {
      _erasedIds.addAll(ids);
      _myStrokeIds.clear();
      _redoStack.clear();
    });
    await _deleteStrokes(ids);
  }

  Future<void> _pickColor(Strings strings) async {
    final controller = TextEditingController(text: Color(_color).toHexString());
    final picked = await showAppDialog<int>(
      context: context,
      builder: (context) => KeyboardAlertDialog(
        content: SizedBox(
          width: 280,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final c in _presetColors)
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(c),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: Color(c),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Theme.of(context).colorScheme.outline,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                decoration: InputDecoration(
                  hintText: strings.noteDrawColorHint,
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      HoneycombColorButton(
                        current: tryParseHexColor(controller.text),
                        onPicked: (picked) =>
                            Navigator.of(context).pop(picked.toARGB32()),
                      ),
                      CopyIconButton(
                        textBuilder: () => hexCopyText(controller.text),
                      ),
                    ],
                  ),
                ),
                onSubmitted: (value) {
                  final parsed = tryParseHexColor(value);
                  if (parsed != null) {
                    Navigator.of(context).pop(parsed.toARGB32());
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
    controller.dispose();
    if (picked != null && mounted) setState(() => _color = picked | 0xFF000000);
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final fg = widget.foreground;
    final selectedBg = fg.withValues(alpha: 0.16);

    Widget toolButton(_DrawTool tool, IconData icon) => IconButton(
      icon: Icon(icon, color: fg),
      tooltip: '',
      style: IconButton.styleFrom(
        backgroundColor: _tool == tool ? selectedBg : null,
      ),
      onPressed: () => setState(() => _tool = tool),
    );

    final toolbar = Material(
      color: widget.background,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 2,
          runSpacing: 2,
          children: [
            toolButton(_DrawTool.pen, Icons.edit),
            toolButton(_DrawTool.eraser, Icons.auto_fix_normal),
            toolButton(_DrawTool.pan, Icons.pan_tool_alt_outlined),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: () => _pickColor(strings),
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: Color(_color),
                  shape: BoxShape.circle,
                  border: Border.all(color: fg.withValues(alpha: 0.5)),
                ),
              ),
            ),
            SizedBox(
              width: 120,
              child: Slider(
                min: 1,
                max: 30,
                value: _width,
                onChanged: (v) => setState(() => _width = v),
              ),
            ),
            IconButton(
              icon: Icon(Icons.undo, color: fg),
              tooltip: '',
              onPressed: _myStrokeIds.isEmpty ? null : _undo,
            ),
            IconButton(
              icon: Icon(Icons.redo, color: fg),
              tooltip: '',
              onPressed: _redoStack.isEmpty ? null : _redo,
            ),
            IconButton(
              icon: Icon(Icons.delete_outline, color: fg),
              tooltip: '',
              onPressed: _visibleStrokes.isEmpty
                  ? null
                  : () => _clearAll(strings),
            ),
            const SizedBox(width: 6),
            // ズーム（2026-10-10追加）。ピンチ・Ctrl＋ホイールでも操作出来る。
            IconButton(
              icon: Icon(Icons.zoom_out, color: fg),
              tooltip: '',
              onPressed: _zoom <= kDrawMinZoom + 0.0001
                  ? null
                  : () => _zoomByStep(1 / kDrawZoomStep),
            ),
            TextButton(
              // 倍率表示。タップで100%（画面幅フィット）へ戻す。
              onPressed: () => _applyZoom(1.0, Offset.zero),
              child: Text(
                '${(_zoom * 100).round()}%',
                style: TextStyle(color: fg),
              ),
            ),
            IconButton(
              icon: Icon(Icons.zoom_in, color: fg),
              tooltip: '',
              onPressed: _zoom >= kDrawMaxZoom - 0.0001
                  ? null
                  : () => _zoomByStep(kDrawZoomStep),
            ),
          ],
        ),
      ),
    );

    return Column(
      children: [
        toolbar,
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              _viewportSize = constraints.biggest;
              // 画面幅フィットの倍率に、ズーム倍率を掛けたものが実効倍率
              // （2026-10-10）。ポインタの座標変換・描画・キャンバスの大きさは
              // 全てこの実効倍率基準。
              final fitScale = constraints.maxWidth / NoteStroke.canvasWidth;
              final scale = fitScale * _zoom;
              final bounds = _contentBounds();
              final origin = bounds.topLeft;
              _syncScrollToOrigin(origin, scale);
              final visible = _visibleStrokes;
              final canvasWidth = bounds.width * scale;
              final contentWidth = math.max(constraints.maxWidth, canvasWidth);
              return Listener(
                key: _viewportKey,
                onPointerDown: _onViewportPointerDown,
                onPointerMove: _onViewportPointerMove,
                onPointerUp: _onViewportPointerEnd,
                onPointerCancel: _onViewportPointerEnd,
                onPointerSignal: _onViewportSignal,
                onPointerPanZoomStart: _onPanZoomStart,
                onPointerPanZoomUpdate: _onPanZoomUpdate,
                child: ColoredBox(
                  color: widget.background,
                  // スクロールバーは太く・常に表示して掴みやすくする（2026-11-05）。標準の
                  // 自動のバー（細く、ホバーするまで見えにくい）は止め、ビューポートの縁に
                  // 縦・横を自前で置く。縦のバーは内側の縦スクロールを`depth == 1`で拾う。
                  child: ScrollConfiguration(
                    behavior: ScrollConfiguration.of(
                      context,
                    ).copyWith(scrollbars: false),
                    child: Scrollbar(
                      controller: _scrollController,
                      notificationPredicate: (n) => n.depth == 1,
                      thumbVisibility: true,
                      interactive: true,
                      thickness: 16,
                      radius: const Radius.circular(8),
                      child: Scrollbar(
                        controller: _hController,
                        thumbVisibility: true,
                        interactive: true,
                        thickness: 16,
                        radius: const Radius.circular(8),
                        child: SingleChildScrollView(
                          controller: _hController,
                          scrollDirection: Axis.horizontal,
                          physics: const NeverScrollableScrollPhysics(),
                          child: SizedBox(
                            width: contentWidth,
                            height: constraints.maxHeight,
                            child: SingleChildScrollView(
                              controller: _scrollController,
                              physics: const NeverScrollableScrollPhysics(),
                              // 縮小で幅が画面幅に満たない時は、キャンバスを中央に置く。
                              child: Center(
                                child: Listener(
                                  onPointerDown: (e) =>
                                      _onPointerDown(e, scale, origin),
                                  onPointerMove: (e) =>
                                      _onPointerMove(e, scale, origin),
                                  onPointerUp: _onPointerEnd,
                                  onPointerCancel: _onPointerEnd,
                                  child: Container(
                                    width: canvasWidth,
                                    height: bounds.height * scale,
                                    color: Colors.white,
                                    child: Stack(
                                      children: [
                                        RepaintBoundary(
                                          child: CustomPaint(
                                            size: Size.infinite,
                                            painter: _StrokesPainter(
                                              visible,
                                              scale,
                                              origin,
                                            ),
                                          ),
                                        ),
                                        CustomPaint(
                                          size: Size.infinite,
                                          painter: _CurrentStrokePainter(
                                            _currentPoints,
                                            Color(_color),
                                            _width,
                                            scale,
                                            origin,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _StrokesPainter extends CustomPainter {
  _StrokesPainter(this.strokes, this.scale, this.origin);

  final List<NoteStroke> strokes;
  final double scale;

  /// 領域の左上の論理座標（負にもなる）。
  final Offset origin;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(scale);
    canvas.translate(-origin.dx, -origin.dy);
    for (final s in strokes) {
      paintNoteStroke(canvas, s);
    }
  }

  @override
  bool shouldRepaint(_StrokesPainter old) =>
      old.scale != scale ||
      old.origin != origin ||
      !identical(old.strokes, strokes);
}

class _CurrentStrokePainter extends CustomPainter {
  _CurrentStrokePainter(
    this.points,
    this.color,
    this.width,
    this.scale,
    this.origin,
  ) : super(repaint: points);

  final ValueNotifier<List<Offset>> points;
  final Color color;
  final double width;
  final double scale;
  final Offset origin;

  @override
  void paint(Canvas canvas, Size size) {
    final list = points.value;
    if (list.isEmpty) return;
    canvas.scale(scale);
    canvas.translate(-origin.dx, -origin.dy);
    paintNoteStroke(
      canvas,
      NoteStroke(
        strokeId: '',
        points: [
          for (final p in list) ...[p.dx, p.dy],
        ],
        color: color.toARGB32(),
        width: width,
        authorId: '',
      ),
    );
  }

  @override
  bool shouldRepaint(_CurrentStrokePainter old) =>
      old.color != color ||
      old.width != width ||
      old.scale != scale ||
      old.origin != origin;
}
