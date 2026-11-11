import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/home_shell_providers.dart';
import '../providers/slide_pick_enabled_provider.dart';
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
    // なぞりの途中で破棄された時は、渡し先の強調を消す（2026-11-11）。
    final target = _handoffTarget;
    if (target != null && _handoffIndex != null) {
      Future.microtask(() => target.pick(null, commit: false));
    }
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

  /// 指の縦位置にある項目。指が項目の上に実際に乗っている時だけ返し、項目の外
  /// （一覧の下の余白・メニューチップとの間など）ではnull（2026-11-07、以前は一番近い
  /// 項目を返していて、チップから少し上へずらしただけで一番下の項目が選ばれていた）。
  int? _indexAt(Offset globalPosition) {
    final dy = globalPosition.dy;
    for (var i = 0; i < widget.itemCount && i < _keys.length; i++) {
      final box = _keys[i].currentContext?.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) continue;
      final top = box.localToGlobal(Offset.zero).dy;
      if (dy >= top && dy <= top + box.size.height) return i;
    }
    return null;
  }

  void _reset() {
    _clearHandoff();
    final wasSliding = _sliding;
    _down = null;
    _sliding = false;
    _index = null;
    if (wasSliding && mounted) setState(() {});
  }

  /// 押した位置からの移動が、はっきり横向き（タブの横ドラッグ）か。経路ではなく、今の位置
  /// だけで毎回判定する（一度横と判断しても、縦へ戻れば縦として扱える）。
  bool _isHorizontalNow(Offset delta) =>
      delta.dx.abs() >= _slop * 2 && delta.dx.abs() > delta.dy.abs() * 1.5;

  void _onMove(PointerMoveEvent event) {
    final down = _down;
    if (down == null) return;
    final delta = event.position - down;
    // なぞりの開始は、メニューチップと同じく向きを問わない（押した位置から[_slop]以上
    // 動けば始まる）。向きで始めるかを決めると、少しの横ぶれで効かなくなっていた
    // （2026-11-05）。「押したまま滑らせて選ぶ」をオフの時は始めない。
    if (!_sliding) {
      if (delta.distance < _slop) return;
      if (!ref.read(slidePickEnabledProvider)) return;
      _sliding = true;
    }
    // 指がこの一覧の外のチップ列などへ出たら、そちらへ選択を渡す（2026-11-05、
    // 項目を押したままメニューチップへ滑らせてタブを切り替える）。横向きの判定より先に
    // 行う（2026-11-11）。コンピューターではチップ列が一覧の左隣に縦に並び、チップへの
    // 動きは横向きが主になる為、先に横向きで止めるとチップへ渡せなかった。
    final other = _bridge.targetAt(event.position);
    if (other != null && other != this) {
      final otherIndex = other.indexAt(event.position);
      if (_handoffTarget != other) {
        _handoffTarget?.pick(null, commit: false);
        _handoffIndex = null;
      }
      _handoffTarget = other;
      if (otherIndex == null) {
        if (_handoffIndex != null) other.pick(null, commit: false);
        _handoffIndex = null;
      } else if (_handoffIndex != otherIndex) {
        _handoffIndex = otherIndex;
        other.pick(otherIndex, commit: false);
      }
      // 一覧側の強調は消す。
      if (_index != null) setState(() => _index = null);
      return;
    }
    _clearHandoff();
    // はっきり横へ動いている間は、項目の強調・選択を動かさない（タブの横ドラッグ）。
    if (_isHorizontalNow(delta)) {
      if (_index != null) setState(() => _index = null);
      return;
    }
    // 別のタブへ切り替わって見えなくなった一覧では、選択を動かさない。
    if (!_visible) return;
    final index = _indexAt(event.position);
    if (index == _index) return;
    setState(() => _index = index);
    // 項目から外れた時は強調だけ消す（離しても何も開かない）。
    if (index != null) widget.onSlide?.call(index);
  }

  // なぞり中の指が一覧の外の登録先（チップ列）へ出ている時の渡し先。
  ItemPickTarget? _handoffTarget;
  int? _handoffIndex;

  void _clearHandoff() {
    if (_handoffIndex != null) _handoffTarget?.pick(null, commit: false);
    _handoffTarget = null;
    _handoffIndex = null;
  }

  void _onUp(Offset position) {
    final index = _index;
    final down = _down;
    // 離した時にはっきり横向きなら、タブの横ドラッグとして項目は開かない。
    final horizontal = down != null && _isHorizontalNow(position - down);
    final wasSliding = _sliding && !horizontal;
    final handoffTarget = _handoffTarget;
    final handoffIndex = _handoffIndex;
    _handoffTarget = null;
    _handoffIndex = null;
    _reset();
    // チップ列の上で離した時は、そのタブで確定する（項目は開かない）。横向きの動きでも
    // 確定する（2026-11-11、渡し先が飛び出したまま残っていた）。
    if (handoffTarget != null) {
      if (handoffIndex != null) {
        handoffTarget.pick(handoffIndex, commit: true);
      } else {
        handoffTarget.pick(null, commit: false);
      }
      return;
    }
    if (wasSliding && index != null) widget.onSlideEnd?.call(index);
  }

  @override
  Widget build(BuildContext context) {
    _visible = PaneVisibility.of(context);
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        // 前の操作の渡し先を引きずらない（2026-11-11）。
        _clearHandoff();
        _down = event.position;
        _sliding = false;
        _index = null;
      },
      onPointerMove: _onMove,
      onPointerUp: (event) => _onUp(event.position),
      onPointerCancel: (_) => _reset(),
      child: widget.builder(context, _keyFor, _sliding ? _index : null),
    );
  }
}

/// スマホの項目一覧（設定・身だしなみ）を、上（標準）か下（メニューチップのすぐ上）へ
/// 置く（2026-11-07）。[bottom]が偽なら従来どおりそのまま返す。下寄せは左揃え（中央にしない）。
/// （2026-11-07、劇画UIだけにあった左・中央・右の揃えは廃止した。）
Widget alignCategoryList(Widget child, {bool bottom = false}) {
  if (!bottom) return child;
  return Align(alignment: Alignment.bottomLeft, child: child);
}
