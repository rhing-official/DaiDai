/// ホイール・トラックパッドのスクロール入力から、「1つ進む／戻る」を決める（2026-11-21）。
///
/// トラックパッドやブラウザによっては、1回の入力が数pxの細かい値で大量に届く。1回ごとに
/// しきい値と比べると全て無視されるので、同じ向きの入力を足し合わせ、[threshold]に達した
/// 時に1つ進める。進めた直後は[cooldown]の間、慣性スクロールの余りで続けて何枚も
/// 飛ばないよう受け付けない。入力が[idleReset]以上途切れたら、足し合わせはやり直す。
class WheelStepper {
  WheelStepper({
    this.threshold = 60,
    this.cooldown = const Duration(milliseconds: 160),
    this.idleReset = const Duration(milliseconds: 250),
  });

  final double threshold;
  final Duration cooldown;
  final Duration idleReset;

  double _accumulated = 0;
  DateTime _lastEvent = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastStep = DateTime.fromMillisecondsSinceEpoch(0);

  /// スクロール量[delta]（下・右が正）を渡す。進めるなら1、戻すなら-1、何もしないなら0。
  int feed(double delta, DateTime now) {
    if (now.difference(_lastEvent) > idleReset) _accumulated = 0;
    _lastEvent = now;
    if (now.difference(_lastStep) < cooldown) return 0;
    // 向きが変わったら、逆向きの分は捨てる。
    if (_accumulated != 0 && (_accumulated > 0) != (delta > 0)) {
      _accumulated = 0;
    }
    _accumulated += delta;
    if (_accumulated.abs() < threshold) return 0;
    final step = _accumulated > 0 ? 1 : -1;
    _accumulated = 0;
    _lastStep = now;
    return step;
  }
}
