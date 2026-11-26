import 'dart:math' as math;

/// 水槽の水面の高さ場（2026-11-26）。細い柱の列（仮想パイプ法、O'Brien・Hodgins）で、
/// 隣り合う柱の水深の差が、柱の間の流れ（[flux]）を加速し、その流れが水を隣へ運ぶ。
/// 水は、運ばれた分だけ増減するので、**量が保たれる**。水は片側から流れ込むと、底を
/// 這って広がり、反対の壁で跳ね返って揺れ、やがて平らに収まる（スロッシング）。
///
/// 水深は、正規化している（1が満水＝チップの高さいっぱい）。
class WaterColumns {
  WaterColumns({this.count = 24, this.gravity = 40000, this.damping = 2.5})
    : depths = List<double>.filled(count, 0),
      flux = List<double>.filled(count - 1, 0);

  /// 柱の数。
  final int count;

  /// 重力（水深の差が流れを加速する強さ）。大きいほど波が速く進む。
  final double gravity;

  /// 流れが減衰する速さ（1/秒）。
  final double damping;

  /// 各柱の水深（0〜[maxDepth]）。
  final List<double> depths;

  /// 柱[i]から柱[i+1]への流れ（水深×柱／秒。正が右向き）。
  final List<double> flux;

  /// 水深の上限。これ以上は、溢れる。
  static const double maxDepth = 1.08;

  /// 時間刻みの上限。波が1ステップで柱の半分以上進むと不安定になる為、これより細かく刻む。
  static const double maxStep = 1 / 300;

  /// [dt]秒進める。
  void step(double dt) {
    var remaining = dt;
    while (remaining > 1e-9) {
      final h = math.min(remaining, maxStep);
      _substep(h);
      remaining -= h;
    }
  }

  void _substep(double dt) {
    final decay = math.exp(-damping * dt);
    for (var i = 0; i < count - 1; i++) {
      var f = (flux[i] + gravity * (depths[i] - depths[i + 1]) * dt) * decay;
      // 水の無い柱から、有る以上は流せない（水深が負にならない）。
      final limit = (f > 0 ? depths[i] : depths[i + 1]) * 0.45 / dt;
      f = f.clamp(-limit, limit);
      flux[i] = f;
    }
    for (var i = 0; i < count; i++) {
      final inflow = i > 0 ? flux[i - 1] : 0.0;
      final outflow = i < count - 1 ? flux[i] : 0.0;
      depths[i] = math.max(0.0, depths[i] + (inflow - outflow) * dt);
    }
  }

  /// 水の量（水深の合計）。満水が[count]。
  double get total => depths.fold(0.0, (a, b) => a + b);

  /// 水位（平均の水深。0〜1）。
  double get level => total / count;

  /// 流れの大きさ。収まったかの判定に使う。
  double get activity {
    var m = 0.0;
    for (final f in flux) {
      m = math.max(m, f.abs());
    }
    return m;
  }

  bool get isEmpty => total < 0.02 && activity < 0.05;

  /// 全ての柱がほぼ満水で、動きが収まっているか。
  bool get isFull =>
      activity < 0.2 && depths.every((d) => d >= 0.985 && d <= 1.03);

  /// 全体を満水にする（動きは止める）。
  void fillInstantly() {
    for (var i = 0; i < count; i++) {
      depths[i] = 1;
    }
    for (var i = 0; i < flux.length; i++) {
      flux[i] = 0;
    }
  }

  /// 位置[x01]（0〜1）の近くへ、水を[volume]足す。入りきらない分（満水を超える分）を返す。
  double add(double x01, double volume, {double spread = 1.6}) {
    final center = x01.clamp(0.0, 1.0) * (count - 1);
    var weightSum = 0.0;
    final weights = List<double>.filled(count, 0);
    for (var i = 0; i < count; i++) {
      final d = (i - center) / spread;
      weights[i] = math.exp(-d * d);
      weightSum += weights[i];
    }
    var leftover = 0.0;
    for (var i = 0; i < count; i++) {
      final share = volume * weights[i] / weightSum;
      final room = maxDepth - depths[i];
      final put = math.min(share, math.max(0.0, room));
      depths[i] += put;
      leftover += share - put;
    }
    return leftover;
  }

  /// 位置[x01]の近くから、水を最大[volume]抜く。抜けた量を返す。
  double remove(double x01, double volume, {double spread = 2.2}) {
    final center = x01.clamp(0.0, 1.0) * (count - 1);
    var weightSum = 0.0;
    final weights = List<double>.filled(count, 0);
    for (var i = 0; i < count; i++) {
      final d = (i - center) / spread;
      weights[i] = math.exp(-d * d);
      weightSum += weights[i];
    }
    var removed = 0.0;
    for (var i = 0; i < count; i++) {
      final share = volume * weights[i] / weightSum;
      final take = math.min(share, depths[i]);
      depths[i] -= take;
      removed += take;
    }
    // 近くの柱が空なら、足りない分は、残りの水から抜く（全体では量が足りる限り）。
    var shortfall = volume - removed;
    if (shortfall > 1e-9) {
      for (var i = 0; i < count && shortfall > 1e-9; i++) {
        final take = math.min(shortfall, depths[i]);
        depths[i] -= take;
        removed += take;
        shortfall -= take;
      }
    }
    return removed;
  }

  /// 位置[x01]を叩いて、そこを中心に水を左右へ押し出す（へこんで、波が広がる）。
  void impulse(double x01, double strength, {double width = 2.2}) {
    final center = x01.clamp(0.0, 1.0) * (count - 1);
    for (var i = 0; i < count - 1; i++) {
      final d = (i + 0.5 - center) / width;
      final push = strength * math.exp(-d * d) * (i + 0.5 < center ? -1 : 1);
      // 水の有る所だけ押し出す。
      final limit = math.min(depths[i], depths[i + 1]) * 8;
      flux[i] += push.clamp(-limit, limit);
    }
  }

  /// 片側へ水を寄せる（傾け）。[side]が1なら右へ、-1なら左へ流れる。
  void tilt(double side, double strength) {
    for (var i = 0; i < count - 1; i++) {
      flux[i] += side * strength * math.min(depths[i], depths[i + 1]);
    }
  }

  /// 位置[x01]（0〜1）の水深（柱の間は線形に補間）。
  double depthAt(double x01) {
    final f = x01.clamp(0.0, 1.0) * (count - 1);
    final i = f.floor().clamp(0, count - 2);
    final t = f - i;
    return depths[i] * (1 - t) + depths[i + 1] * t;
  }
}
