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

class _SwipeDownDockState extends State<SwipeDownDock> {
  int? _pointer;
  Offset? _start;

  void _reset() {
    _pointer = null;
    _start = null;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (e) {
        if (!widget.enabled || _pointer != null) return;
        final height = MediaQuery.sizeOf(context).height;
        if (e.position.dy > height - widget.bottomReserve) return;
        _pointer = e.pointer;
        _start = e.position;
      },
      onPointerUp: (e) {
        if (e.pointer != _pointer) return;
        final start = _start;
        _reset();
        if (start == null || !widget.enabled) return;
        final d = e.position - start;
        if (d.dy >= widget.minDistance && d.dx.abs() <= d.dy * 0.6) {
          widget.onDock();
        }
      },
      onPointerCancel: (e) {
        if (e.pointer == _pointer) _reset();
      },
      child: widget.child,
    );
  }
}
