import 'package:flutter/material.dart';

/// 通話画面の下スワイプ（ミニ表示にする）の判定（2026-11-16）。ジェスチャーのアリーナには
/// 参加せず、生のポインターで判定する。ウィンドウのタップ・ピンのボタン・横スクロールの帯など、
/// 子孫のジェスチャーに負けて効かなくなる（beta.7で、映像がある通話の下スワイプが効かなかった）
/// ことが無いようにする為。押した位置から[minDistance]以上、ほぼ真下へ動いて離したら[onDock]。
/// 下端の[bottomReserve]の中（操作ボタン列）から始めた動きは数えない。
class SwipeDownDock extends StatefulWidget {
  const SwipeDownDock({
    required this.child,
    required this.onDock,
    this.enabled = true,
    this.minDistance = 60,
    this.bottomReserve = 160,
    super.key,
  });

  final Widget child;
  final VoidCallback onDock;
  final bool enabled;
  final double minDistance;
  final double bottomReserve;

  @override
  State<SwipeDownDock> createState() => _SwipeDownDockState();
}

/// 子孫（ウィンドウの拡縮、`CallZoomable`）から、今の操作を下スワイプとして数えないよう
/// 求める窓口（2026-11-17）。ピンチ・拡大中の移動の後に、残った指が少し動いて離れても
/// ミニ表示にならないようにする。
class SwipeDownDockGuard {
  SwipeDownDockGuard._(this._state);

  final _SwipeDownDockState _state;

  /// 今の操作（全ての指が離れるまで）を、下スワイプとして数えない。
  void cancel() => _state._cancelled = true;

  static SwipeDownDockGuard? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_SwipeDownDockScope>()?.guard;
}

class _SwipeDownDockScope extends InheritedWidget {
  const _SwipeDownDockScope({required this.guard, required super.child});

  final SwipeDownDockGuard guard;

  @override
  bool updateShouldNotify(_SwipeDownDockScope old) => false;
}

class _SwipeDownDockState extends State<SwipeDownDock> {
  late final SwipeDownDockGuard _guard = SwipeDownDockGuard._(this);

  /// 触れている指の数。2本目が触れたら（ピンチ）、全部離れるまでその操作は数えない。
  int _down = 0;
  bool _cancelled = false;
  int? _pointer;
  Offset? _start;

  void _release() {
    if (_down > 0) _down--;
    if (_down == 0) {
      _pointer = null;
      _start = null;
      _cancelled = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SwipeDownDockScope(
      guard: _guard,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (e) {
          _down++;
          if (_down > 1) {
            _cancelled = true;
            return;
          }
          if (!widget.enabled) return;
          final height = MediaQuery.sizeOf(context).height;
          if (e.position.dy > height - widget.bottomReserve) return;
          _pointer = e.pointer;
          _start = e.position;
        },
        onPointerUp: (e) {
          final start = _start;
          final tracked = e.pointer == _pointer;
          final cancelled = _cancelled;
          _release();
          if (!tracked || cancelled || start == null || !widget.enabled) {
            return;
          }
          final d = e.position - start;
          if (d.dy >= widget.minDistance && d.dx.abs() <= d.dy * 0.6) {
            widget.onDock();
          }
        },
        onPointerCancel: (e) => _release(),
        child: widget.child,
      ),
    );
  }
}
