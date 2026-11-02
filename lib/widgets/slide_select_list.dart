import 'package:flutter/material.dart';

import '../models/nav_chip_layout.dart';

/// 項目一覧（設定・身だしなみのカテゴリ一覧）の上を、指やマウスで縦になぞって選べるように
/// する（2026-11-02、メニューチップの「なぞって切り替え」と同じ操作。チップのように項目を
/// 浮かせる演出は付けない）。
///
/// 一覧のスクロールやタップは奪わず（`Listener`で見るだけ）、押した位置から縦方向へ
/// [_slop]以上動いた時だけ「なぞり」とみなす。なぞっている間、指の下の項目が変わるたびに
/// [onSlide]を呼ぶ。指を離した時は、なぞっていた場合だけ最後にいた項目を[onSlideEnd]へ渡す。
/// [builder]は、各項目を`KeyedSubtree(key: keyFor(i))`で包んで返す（指の位置の判定に使う）。
class SlideSelectList extends StatefulWidget {
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
  State<SlideSelectList> createState() => _SlideSelectListState();
}

class _SlideSelectListState extends State<SlideSelectList> {
  static const _slop = 12.0;

  final List<GlobalKey> _keys = [];
  Offset? _down;
  bool _sliding = false;
  int? _index;

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
    _index = null;
    if (wasSliding && mounted) setState(() {});
  }

  void _onMove(PointerMoveEvent event) {
    final down = _down;
    if (down == null) return;
    if (!_sliding) {
      final delta = event.position - down;
      if (delta.dy.abs() < _slop || delta.dy.abs() < delta.dx.abs()) return;
      _sliding = true;
    }
    final index = _indexAt(event.position);
    if (index == null || index == _index) return;
    setState(() => _index = index);
    widget.onSlide?.call(index);
  }

  void _onUp() {
    final index = _index;
    final wasSliding = _sliding;
    _reset();
    if (wasSliding && index != null) widget.onSlideEnd?.call(index);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        _down = event.position;
        _sliding = false;
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
