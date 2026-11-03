import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/nav_chip_layout.dart';
import '../providers/home_shell_providers.dart';
import 'pane_visibility.dart';

/// 項目一覧（設定・身だしなみのカテゴリ一覧）の上を、指やマウスで縦になぞって選べるように
/// する（2026-11-02、メニューチップの「なぞって切り替え」と同じ操作。チップのように項目を
/// 浮かせる演出は付けない）。
///
/// 一覧のスクロールやタップは奪わず（`Listener`で見るだけ）、押した位置から縦方向へ
/// [_slop]以上動いた時だけ「なぞり」とみなす。なぞっている間、指の下の項目が変わるたびに
/// [onSlide]を呼ぶ。指を離した時は、なぞっていた場合だけ最後にいた項目を[onSlideEnd]へ渡す。
/// [builder]は、各項目を`KeyedSubtree(key: keyFor(i))`で包んで返す（指の位置の判定に使う）。
class SlideSelectList extends ConsumerStatefulWidget {
  const SlideSelectList({
    required this.itemCount,
    required this.builder,
    this.onSlide,
    this.onSlideEnd,
    super.key,
  });

  final int itemCount;
  final ValueChanged<int>? onSlide;
  final ValueChanged<int>? onSlideEnd;

  /// [slidingIndex]は、今なぞっていて指の下にある項目（なぞっていなければnull）。
  final Widget Function(
    BuildContext context,
    GlobalKey Function(int index) keyFor,
    int? slidingIndex,
  )
  builder;

  @override
  ConsumerState<SlideSelectList> createState() => _SlideSelectListState();
}

class _SlideSelectListState extends ConsumerState<SlideSelectList>
    implements ItemPickTarget {
  static const _slop = 12.0;

  final List<GlobalKey> _keys = [];
  Offset? _down;
  bool _sliding = false;

  /// このタッチは横ドラッグ（タブの切り替えなど）と判断した。離すまで、なぞりも選択もしない。
  bool _horizontal = false;
  int? _index;

  late final ItemPickBridge _bridge;
  bool _visible = true;

  @override
  void initState() {
    super.initState();
    _bridge = ref.read(itemPickBridgeProvider)..register(this);
  }

  @override
  void dispose() {
    _bridge.unregister(this);
    super.dispose();
  }

  RenderBox? get _box {
    final box = context.findRenderObject();
    return box is RenderBox && box.attached && box.hasSize ? box : null;
  }

  /// 指の位置に、この一覧が（他の層に覆われず）当たるか。
  @override
  bool isActiveAt(Offset globalPosition) {
    if (!mounted || !_visible) return false;
    final box = _box;
    if (box == null) return false;
    final result = HitTestResult();
    WidgetsBinding.instance.hitTestInView(
      result,
      globalPosition,
      View.of(context).viewId,
    );
    return result.path.any((entry) => entry.target == box);
  }

  @override
  int? indexAt(Offset globalPosition) =>
      isActiveAt(globalPosition) ? _indexAt(globalPosition) : null;

  @override
  void pick(int? index, {required bool commit}) {
    if (!mounted) return;
    if (index == null) {
      if (_sliding || _index != null) {
        setState(() {
          _sliding = false;
          _index = null;
        });
      }
      return;
    }
    if (commit) {
      setState(() {
        _sliding = false;
        _index = null;
      });
      widget.onSlideEnd?.call(index);
      return;
    }
    if (_sliding && _index == index) return;
    setState(() {
      _sliding = true;
      _index = index;
    });
    widget.onSlide?.call(index);
  }

  GlobalKey _keyFor(int index) {
    while (_keys.length <= index) {
      _keys.add(GlobalKey());
    }
    return _keys[index];
  }

  /// 指の縦位置にある項目。項目と項目の隙間は、近い方に含める。
  int? _indexAt(Offset globalPosition) {
    int? best;
    var bestDistance = double.infinity;
    for (var i = 0; i < widget.itemCount && i < _keys.length; i++) {
      final box = _keys[i].currentContext?.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) continue;
      final top = box.localToGlobal(Offset.zero).dy;
      final bottom = top + box.size.height;
      final dy = globalPosition.dy;
      final distance = dy < top ? top - dy : (dy > bottom ? dy - bottom : 0.0);
      if (distance < bestDistance) {
        bestDistance = distance;
        best = i;
      }
    }
    return best;
  }

  void _reset() {
    final wasSliding = _sliding;
    _down = null;
    _sliding = false;
    _horizontal = false;
    _index = null;
    if (wasSliding && mounted) setState(() {});
  }

  void _onMove(PointerMoveEvent event) {
    final down = _down;
    if (down == null) return;
    if (_horizontal) return;
    final delta = event.position - down;
    if (!_sliding) {
      // 先に閾値を超えた軸で向きを決める。横が先なら、離すまでこのタッチでは何もしない
      // （横ドラッグの出だしの縦のぶれで、離した時に項目が開いてしまわないように）。
      if (delta.dx.abs() >= _slop && delta.dx.abs() > delta.dy.abs()) {
        _horizontal = true;
        return;
      }
      if (delta.dy.abs() < _slop || delta.dy.abs() < delta.dx.abs()) return;
      _sliding = true;
    } else if (delta.dx.abs() >= _slop * 2 && delta.dx.abs() > delta.dy.abs()) {
      // なぞり中に、横の動きが縦を上回った。横ドラッグへの切り替えとみなして取り消す。
      _horizontal = true;
      _sliding = false;
      _index = null;
      setState(() {});
      return;
    }
    final index = _indexAt(event.position);
    if (index == null || index == _index) return;
    setState(() => _index = index);
    widget.onSlide?.call(index);
  }

  void _onUp() {
    final index = _index;
    final wasSliding = _sliding && !_horizontal;
    _reset();
    if (wasSliding && index != null) widget.onSlideEnd?.call(index);
  }

  @override
  Widget build(BuildContext context) {
    _visible = PaneVisibility.of(context);
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        _down = event.position;
        _sliding = false;
        _horizontal = false;
        _index = null;
      },
      onPointerMove: _onMove,
      onPointerUp: (_) => _onUp(),
      onPointerCancel: (_) => _reset(),
      child: widget.builder(context, _keyFor, _sliding ? _index : null),
    );
  }
}

/// スマホの項目一覧（設定・身だしなみ）を左・中央・右に寄せる（2026-11-02、劇画UIのみ）。
/// [alignment]がnullなら従来どおり全幅。指定時は幅を絞った一覧を、上端はそのままに
/// 左端・中央・右端（一覧の右端が画面の右端）へ置く。
Widget alignCategoryList(NavChipAlignment? alignment, Widget child) {
  if (alignment == null) return child;
  return Align(
    alignment: switch (alignment) {
      NavChipAlignment.start => Alignment.topLeft,
      NavChipAlignment.center => Alignment.topCenter,
      NavChipAlignment.end => Alignment.topRight,
    },
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 300),
      child: child,
    ),
  );
}
