import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/home_shell_providers.dart';
import 'pane_visibility.dart';

/// メニューチップから始めたタッチを、そのまま滑らせて操作できる部品（ボタン・タブ）にする
/// （2026-11-03、`ItemPickBridge`）。包んだ部品の上に指が来ると少し大きくなり
/// （[onEnter]を呼ぶ）、そこで指を離すと[onCommit]を呼ぶ。通常のタップや長押しには
/// 影響しない。表示中の画面（`PaneVisibility`）の部品だけが対象になる。
///
/// メニューチップからだけでなく、この部品自身を押したまま別の`PickZone`へ滑らせても
/// 同じように選べる（2026-11-03）。元の部品で離した（ふつうのタップ）時は何も足さず、
/// 別の部品の上で離した時だけ、その部品の[onCommit]を呼ぶ（元の部品へ戻ってきた時は
/// [onEnter]を呼ぶ。一対・広場のタブで、行って戻る往復を続けて切り替えられるように）。
class PickZone extends ConsumerStatefulWidget {
  const PickZone({
    required this.child,
    this.onEnter,
    this.onCommit,
    this.slideFrom = true,
    super.key,
  });

  /// この部品を押した指を、別の部品へ滑らせて選べるようにするか。押した瞬間に自分で
  /// 操作を始める部品（並べ替えボタンなど）はfalseにする。
  final bool slideFrom;

  final Widget child;

  /// 指が乗った時（例: 一対・広場のタブはここで切り替える）。
  final VoidCallback? onEnter;

  /// 指がここで離れた時（例: ボタンを押した扱いにする）。
  final VoidCallback? onCommit;

  @override
  ConsumerState<PickZone> createState() => _PickZoneState();
}

class _PickZoneState extends ConsumerState<PickZone> implements ItemPickTarget {
  late final ItemPickBridge _bridge;
  bool _visible = true;
  bool _hot = false;

  // この部品から始めたタッチ（別の部品へ滑らせる用）。
  bool _touching = false;
  ItemPickTarget? _lastTarget;
  int? _lastIndex;
  bool _left = false;

  void _onDown(PointerDownEvent event) {
    if (!widget.slideFrom) return;
    if (event.kind == PointerDeviceKind.mouse &&
        event.buttons != kPrimaryMouseButton) {
      return;
    }
    _touching = true;
    _left = false;
    _lastTarget = null;
    _lastIndex = null;
  }

  void _onMove(PointerMoveEvent event) {
    if (!_touching) return;
    final target = _bridge.targetAt(event.position);
    final index = target?.indexAt(event.position);
    if (target == null || index == null) {
      _clearLast();
      return;
    }
    // 元の部品の上にいる間は何もしない（別の部品へ一度出てから戻った時だけ扱う）。
    if (target == this && !_left) return;
    if (target != this) _left = true;
    if (_lastTarget != target) {
      _lastTarget?.pick(null, commit: false);
      _lastIndex = null;
    }
    _lastTarget = target;
    if (_lastIndex != index) {
      _lastIndex = index;
      target.pick(index, commit: false);
    }
  }

  void _clearLast() {
    if (_lastIndex != null) _lastTarget?.pick(null, commit: false);
    _lastTarget = null;
    _lastIndex = null;
  }

  void _onEnd({required bool commit}) {
    final target = _lastTarget;
    final index = _lastIndex;
    _touching = false;
    _lastTarget = null;
    _lastIndex = null;
    if (target == null || index == null) return;
    // 元の部品に戻って離した時は、ふつうのタップとして扱う（二重に実行しない）。
    target.pick(
      commit && target != this ? index : null,
      commit: commit && target != this,
    );
  }

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

  @override
  bool isActiveAt(Offset globalPosition) {
    if (!mounted || !_visible) return false;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return false;
    final result = HitTestResult();
    WidgetsBinding.instance.hitTestInView(
      result,
      globalPosition,
      View.of(context).viewId,
    );
    return result.path.any((entry) => entry.target == box);
  }

  @override
  int? indexAt(Offset globalPosition) => isActiveAt(globalPosition) ? 0 : null;

  @override
  void pick(int? index, {required bool commit}) {
    if (!mounted) return;
    if (index == null) {
      if (_hot) setState(() => _hot = false);
      return;
    }
    if (commit) {
      if (_hot) setState(() => _hot = false);
      widget.onCommit?.call();
      return;
    }
    if (!_hot) {
      setState(() => _hot = true);
      widget.onEnter?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    _visible = PaneVisibility.of(context);
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onDown,
      onPointerMove: _onMove,
      onPointerUp: (_) => _onEnd(commit: true),
      onPointerCancel: (_) => _onEnd(commit: false),
      child: AnimatedScale(
        scale: _hot ? 1.1 : 1.0,
        duration: const Duration(milliseconds: 120),
        child: widget.child,
      ),
    );
  }
}
