import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'water_columns.dart';

/// 1つの水槽（チップ・項目・タブ）。水は、柱の列（[WaterColumns]）で、量が保たれる。
class LiquidTank {
  final WaterColumns water = WaterColumns();

  /// 水位（0〜1）。
  double get level => water.level;

  /// 空か（水が無く、流れも収まっている）。
  bool get isEmpty => water.isEmpty;

  /// 満水で、動きも収まっているか。
  bool get isFull => water.isFull;
}

/// 水滴・飛沫の1粒。
class LiquidDrop {
  LiquidDrop(this.pos, this.vel, this.radius, this.life);

  Offset pos;
  Offset vel;
  final double radius;
  final double life;
  double age = 0;
}

const double kLiquidGravity = 1400; // ピクセル/秒²。画面の下向き。

/// 水が流れる量（水槽1つ分＝柱の数を、この秒数で移す）。
const double _kFillSeconds = 0.55;

/// 元の項目から次の項目へ注ぐ、放物線の水の流れ。元の項目の水を抜き、次の項目へ入れる
/// （量が保たれる）。
class LiquidStream {
  LiquidStream({
    required this.from,
    required this.to,
    required this.p0,
    required this.p1,
    required this.width,
    required this.drainX,
    required this.drainSpread,
    required this.entryX,
    this.delay = 0,
    this.headTime = 0.30,
    this.isLast = true,
    double? flightOverride,
  }) : flight =
           flightOverride ??
           (0.26 + (p1 - p0).distance / 3000).clamp(0.26, 0.5),
       t = -delay;

  final int from;
  final int to;
  final Offset p0;
  final Offset p1;

  /// 流れの太さ（ピクセル）。項目の大きさから決める。
  final double width;

  /// 元の項目で、水を抜く位置（0〜1）と広がり。進む側の壁際から抜く。
  final double drainX;
  final double drainSpread;

  /// 次の項目で、水が入る位置（0〜1）。元の側の壁際から入る。
  final double entryX;

  /// 始まるまでの待ち（秒）。何個も跨ぐ時、前の流れが着く少し前に始める。
  final double delay;

  /// 先端が着くまでの時間（秒）。何個も跨ぐ時は、1つあたりを短くする。
  final double headTime;

  /// 最後の1つか。
  final bool isLast;

  /// 放物線の形を決める飛行時間（秒）。
  final double flight;

  /// 経過時間。始まるまでは負（受け渡しの待ち）。
  double t;
  bool started = false;
  bool arrived = false;
  bool broke = false;

  /// 手前の流れ（何個も跨ぐ時、この流れの元の項目へ水を送ってくる流れ）。手前が出し切る
  /// まで、この流れは元の項目が空になっても終わらない（途中の項目に水を取り残さない）。
  LiquidStream? upstream;

  /// 手前の流れが、もう水を送ってこないか。
  bool get upstreamDone {
    final u = upstream;
    return u == null || (u.dryAt != null && u.inFlight.isEmpty);
  }

  /// 元の項目に水があった事が有るか（空になった事を、始まる前と区別する為）。
  bool hadWater = false;

  /// 元の項目が空になった時刻（まだなら`null`）。
  double? dryAt;

  /// いま流れている量の、最大に対する割合（0〜1）。太さに使う。
  double flowNow = 0;

  /// 空中を飛んでいる水（着く時刻、量）。
  final List<(double, double)> inFlight = [];

  /// 元の側が離れ始めてからの経過（まだなら0）。
  double get tailAge => dryAt == null ? 0 : (t - dryAt!);

  bool get finished => dryAt != null && tailAge >= 0.34 && inFlight.isEmpty;

  double get _vx => (p1.dx - p0.dx) / flight;
  double get _vy0 =>
      ((p1.dy - p0.dy) - 0.5 * kLiquidGravity * flight * flight) / flight;

  /// 位置[u]（0〜1）。
  Offset at(double u) {
    final tau = u.clamp(0.0, 1.0) * flight;
    return Offset(
      p0.dx + _vx * tau,
      p0.dy + _vy0 * tau + 0.5 * kLiquidGravity * tau * tau,
    );
  }

  /// 位置[u]での速度。
  Offset velocityAt(double u) {
    final tau = u.clamp(0.0, 1.0) * flight;
    return Offset(_vx, _vy0 + kLiquidGravity * tau);
  }
}

/// 水の動きの計算（2026-11-26）。描くことは含まない。項目の矩形と選択を受け取り、水を
/// 元の項目から次の項目へ移す（量は保たれる）。水は、次の項目の片側から入り、底を這って
/// 広がり、反対の壁で跳ね返って揺れ、平らに溜まる。重力は常に画面の下。
class LiquidSim extends ChangeNotifier {
  /// 各項目の矩形（描く層の座標。飛び出しを含まない静止位置）。
  List<Rect?> rects = const [];

  /// 各項目の、目に見える箱（`rects`の中。行の幅より縮めている時だけ違う）。無ければ`rects`。
  List<Rect?> blocks = const [];

  /// 項目[i]の、目に見える範囲。
  Rect? visible(int i) {
    final b = i < blocks.length ? blocks[i] : null;
    return b ?? (i < rects.length ? rects[i] : null);
  }

  final Map<int, LiquidTank> tanks = {};
  final List<LiquidDrop> drops = [];
  final math.Random _rng = math.Random(7);

  /// 水の流れ。何個も跨ぐ時は、順に受け渡す複数本になる。
  final List<LiquidStream> streams = [];

  /// いま選ばれている項目。
  int? selected;

  LiquidTank tank(int i) => tanks.putIfAbsent(i, LiquidTank.new);

  void repaint() => notifyListeners();

  /// 最初に測れた時、[index]は最初から満水にする（流れは出さない）。
  void fillInstantly(int index) {
    selected = index;
    tank(index).water.fillInstantly();
  }

  /// 選択が[prev]から[next]へ移った時の、水の流れを始める。間に項目が有れば、それぞれへ
  /// 流れ込みながら、次の項目へ流れ込む（途中の項目は、水が溜まって、また抜ける）。
  void startTransition(int? prev, int? next) {
    selected = next;
    // 空中にあった水は、それぞれの行き先へ入れておく（量を失わない）。
    for (final st in streams) {
      for (final (_, volume) in st.inFlight) {
        tank(st.to).water.add(st.entryX, volume);
      }
    }
    streams.clear();
    if (next == null) return;
    // 水が残っている項目（前の選択だけでなく、移動の途中で水が溜まった項目も）は、全て
    // 次の項目へ流す。
    final sources = <int>[
      for (final e in tanks.entries)
        if (e.key != next && e.value.level >= 0.08) e.key,
    ];
    if (prev != null &&
        prev != next &&
        !sources.contains(prev) &&
        (tanks[prev]?.level ?? 0) >= 0.08) {
      sources.add(prev);
    }
    sources.sort((a, b) => (a - next).abs().compareTo((b - next).abs()));
    for (final source in sources) {
      _startChain(source, next, tiltFirst: source == prev);
    }
  }

  /// [source]から[next]へ、1つずつ進む順（途中の項目を含む）に、流れを繋げる。
  void _startChain(int source, int next, {required bool tiltFirst}) {
    final step = next > source ? 1 : -1;
    // 間の項目には水を溜めない（何個跨いでも、元の項目から次の項目へ直接移す）。
    final path = <int>[source, next];
    assert(step != 0);
    final hops = path.length - 1;
    // 何個も跨ぐ時は、1つあたりを短くする。
    final headTime = (0.30 - 0.04 * (hops - 1)).clamp(0.16, 0.30);
    var delay = 0.0;
    final chain = <LiquidStream>[];
    for (var k = 0; k < hops; k++) {
      final stream = _makeStream(
        path[k],
        path[k + 1],
        delay: delay,
        headTime: headTime,
        isLast: k == hops - 1,
        tiltFirst: k == 0 && tiltFirst,
      );
      if (stream == null) return;
      if (chain.isNotEmpty) stream.upstream = chain.last;
      chain.add(stream);
      // 次の流れは、この流れが着く少し前に始める（流れ込みながら、次へ流れ込む）。
      delay += headTime * 0.75;
    }
    streams.addAll(chain);
  }

  LiquidStream? _makeStream(
    int from,
    int to, {
    required double delay,
    required double headTime,
    required bool isLast,
    required bool tiltFirst,
  }) {
    final rectFrom = visible(from);
    final rectTo = visible(to);
    if (rectFrom == null || rectTo == null) return null;
    final halfH = rectFrom.height / 2;
    final dx = rectTo.center.dx - rectFrom.center.dx;
    final dy = rectTo.center.dy - rectFrom.center.dy;
    // 横に並んでいる（高さ方向のずれが小さい）時は、進む側の縁から溢れる。
    final horizontal = dx.abs() > dy.abs() * 1.2;
    final Offset p0;
    final double drainX;
    final double drainSpread;
    double entryX;
    if (horizontal) {
      final s = dx >= 0 ? 1.0 : -1.0;
      // 横から流れ込む: 水面の高さで、進む側の壁を越えて、次の項目の壁へ低く流れる
      // （上から落とさない）。
      p0 = Offset(
        s > 0 ? rectFrom.right - 3 : rectFrom.left + 3,
        rectFrom.bottom - halfH * 0.7,
      );
      drainX = s > 0 ? 0.92 : 0.08;
      drainSpread = 2.4;
      entryX = s > 0 ? 0.04 : 0.96;
      if (tiltFirst) tank(from).water.tilt(s, 6);
    } else {
      // 縦に並ぶ時。上へは、水が右へ寄って上がり、右端から上の項目へ流れる。下へは、水が
      // 左へ寄って下がり、左端から下の項目へ流れる。流れは、水が実際に有る所から出す。
      final up = dy < 0;
      final s = up ? 1.0 : -1.0;
      drainX = up ? 0.9 : 0.1;
      drainSpread = 3;
      p0 = Offset(
        rectFrom.left + rectFrom.width * drainX,
        up ? rectFrom.top : rectFrom.bottom - halfH * 0.1,
      );
      // 次の項目へは、同じ横位置（その項目の幅の中）から入る。
      entryX = ((p0.dx - rectTo.left) / rectTo.width).clamp(0.08, 0.92);
      if (tiltFirst) tank(from).water.tilt(s, 6);
    }
    final entryPx = rectTo.left + rectTo.width * entryX;
    final p1 = Offset(
      entryPx,
      horizontal
          ? rectTo.bottom - rectTo.height * 0.35
          : rectTo.center.dy - rectTo.height * 0.3,
    );
    final width = (math.min(rectFrom.width, rectFrom.height) * 0.32).clamp(
      7.0,
      16.0,
    );
    return LiquidStream(
      from: from,
      to: to,
      p0: p0,
      p1: p1,
      width: width,
      drainX: drainX,
      drainSpread: drainSpread,
      entryX: entryX,
      delay: delay,
      headTime: headTime,
      isLast: isLast,
      flightOverride: horizontal ? 0.16 : null,
    );
  }

  /// [dt]秒進める。まだ動いていれば`true`。
  bool step(double dt) {
    var active = false;
    final capacity = WaterColumns().count.toDouble();
    final rate = capacity / _kFillSeconds; // 流れの量（水深×柱／秒）。

    // 流れ: 元の項目から水を抜き、空中を飛ばして、次の項目へ入れる。
    for (final st in streams) {
      st.t += dt;
      active = true;
      if (st.t < 0) continue;
      final source = tank(st.from);
      final target = tank(st.to);
      st.started = true;
      if (st.dryAt == null) {
        // 途中の項目は、少し遅く抜く（水が溜まって見える）。
        final want = rate * dt * (st.upstream == null ? 1.0 : 0.75);
        final removed = source.water.remove(
          st.drainX,
          want,
          spread: st.drainSpread,
        );
        if (removed > 0) st.hadWater = true;
        st.flowNow += ((removed / want) - st.flowNow) * 0.3;
        if (removed > 0) st.inFlight.add((st.t + st.headTime, removed));
        // 水を抜き切ったら、元の側が離れる。
        if (st.hadWater && st.upstreamDone && source.water.total < 0.05) {
          st.dryAt = st.t;
        }
      } else {
        st.flowNow *= 0.85;
      }
      // 流れている間、縁から細かい水滴が飛び散る。
      if (st.dryAt == null && st.flowNow > 0.25 && _rng.nextDouble() < 0.7) {
        final u = _rng.nextDouble() * 0.5;
        final v = st.velocityAt(u);
        drops.add(
          LiquidDrop(
            st.at(u),
            v * 0.5 +
                Offset(
                  (_rng.nextDouble() - 0.5) * 140,
                  -_rng.nextDouble() * 90,
                ),
            1.2 + _rng.nextDouble() * 1.8,
            0.4 + _rng.nextDouble() * 0.4,
          ),
        );
      }
      // 空中の水が、着く時刻になったら、次の項目へ入る。
      while (st.inFlight.isNotEmpty && st.inFlight.first.$1 <= st.t) {
        final volume = st.inFlight.removeAt(0).$2;
        final leftover = target.water.add(st.entryX, volume);
        if (!st.arrived) {
          st.arrived = true;
          _impact(st.to, st.p1, 1.4, splash: st.isLast);
        }
        if (leftover > 0.02) _spill(st.to, st.p1);
      }
      // 元の側が離れると、流れが途中でちぎれて、数滴の水滴になって落ちる。
      if (!st.broke && st.dryAt != null && st.tailAge >= 0.08) {
        st.broke = true;
        for (var k = 0; k < 9; k++) {
          final u = 0.4 + k * 0.07;
          final v = st.velocityAt(u);
          drops.add(
            LiquidDrop(
              st.at(u),
              v + Offset((k - 4) * 26.0, -40.0 * (k.isEven ? 1 : 0.4)),
              2.8 - (k % 3) * 0.5,
              0.9,
            ),
          );
        }
      }
    }
    streams.removeWhere((st) => st.finished);

    // 流れの無い水槽: 選ばれた項目は満水まで溜め直し、他は静かに空にする（取りこぼし対策）。
    for (final entry in tanks.entries) {
      final i = entry.key;
      final water = entry.value.water;
      final busy = streams.any((s) => s.from == i || s.to == i);
      if (!busy) {
        if (i == selected) {
          if (water.level < 0.9995) {
            water.add(0.5, math.min(rate * 0.8 * dt, capacity - water.total));
          }
        } else if (water.total > 0.01) {
          water.remove(0.5, rate * 0.7 * dt, spread: 8);
        } else if (water.total > 0) {
          water.remove(0.5, water.total, spread: 8);
        }
      }
      water.step(dt);
      final settledFull = i == selected && water.isFull;
      if (!settledFull && !water.isEmpty) active = true;
      if (i == selected && water.level < 0.9995) active = true;
    }

    // 水滴: 重力で落ち、水槽に当たると水面を叩く。
    for (final drop in drops) {
      drop.vel += Offset(0, kLiquidGravity * dt);
      drop.pos += drop.vel * dt;
      drop.age += dt;
      if (drop.vel.dy > 0) {
        for (var i = 0; i < rects.length; i++) {
          final r = visible(i);
          if (r == null) continue;
          if (r.deflate(r.shortestSide * 0.18).contains(drop.pos)) {
            final t = tanks[i];
            if (t != null && t.level > 0.2) {
              _impact(i, drop.pos, 0.5, splash: false);
              drop.age = drop.life;
            }
          }
        }
      }
    }
    drops.removeWhere((d) => d.age >= d.life);
    if (drops.isNotEmpty) active = true;

    return active;
  }

  /// 項目[i]の、位置[at]に水が当たった。水面を叩き、[splash]なら水滴を上げる。
  void _impact(int i, Offset at, double strength, {required bool splash}) {
    final r = visible(i);
    if (r == null) return;
    final x01 = ((at.dx - r.left) / r.width).clamp(0.0, 1.0);
    tank(i).water.impulse(x01, strength);
    if (!splash) return;
    // 飛沫: ふんだんに（左右へ広く、高さも粒の大きさもばらつかせる）。
    final rnd = math.Random((at.dx * 31 + at.dy * 17 + i * 7).toInt());
    final n = (10 + 14 * strength).round();
    for (var k = 0; k < n; k++) {
      final spread = (rnd.nextDouble() - 0.5) * 340.0;
      drops.add(
        LiquidDrop(
          at,
          Offset(spread, -(120 + rnd.nextDouble() * 260)),
          1.4 + rnd.nextDouble() * 2.2,
          0.5 + rnd.nextDouble() * 0.5,
        ),
      );
    }
  }

  /// 満水の項目に、まだ水が入ってきた。縁から溢れて、水滴が落ちる。
  void _spill(int i, Offset at) {
    final rnd = math.Random(at.dx.toInt() + i);
    for (var k = 0; k < 6; k++) {
      drops.add(
        LiquidDrop(
          at + Offset((rnd.nextDouble() - 0.5) * 16, -4),
          Offset(
            (rnd.nextDouble() - 0.5) * 240,
            -(70 + rnd.nextDouble() * 120),
          ),
          1.6 + rnd.nextDouble() * 1.6,
          0.5 + rnd.nextDouble() * 0.3,
        ),
      );
    }
  }

  /// 項目[i]の水面より下の領域（項目の左上を原点にした[size]の座標）。満水なら全体、
  /// 空なら空の経路。[inset]は、枠の内側に収める余白。
  Path waterRegion(int i, Size size, {double inset = 0}) {
    final t = tanks[i];
    // 行の幅より縮めた箱が有る時は、水を、その箱の中だけに張る（箱の位置へずらす）。
    final row = i < rects.length ? rects[i] : null;
    final blk = i < blocks.length ? blocks[i] : null;
    var origin = Offset.zero;
    var area = size;
    if (row != null &&
        blk != null &&
        (row.width - size.width).abs() < 1 &&
        (row.height - size.height).abs() < 1) {
      origin = blk.topLeft - row.topLeft;
      area = blk.size;
    }
    final full = Rect.fromLTWH(
      origin.dx + inset,
      origin.dy + inset,
      area.width - inset * 2,
      area.height - inset * 2,
    );
    if (t == null || t.isEmpty) return Path();
    if (t.isFull) return Path()..addRect(full);
    final water = t.water;
    final bottom = full.bottom;
    const samples = 32;
    final path = Path()..moveTo(full.left - 2, bottom + 2);
    for (var s = 0; s <= samples; s++) {
      final x01 = s / samples;
      final depth = water.depthAt(x01);
      // 壁際は、水面が少し持ち上がる（メニスカス）。水が有る所だけ。
      final d = math.min(x01, 1 - x01) * full.width;
      final meniscus = depth > 0.02 ? 2.2 * math.exp(-d / 4) : 0.0;
      final y = bottom - depth * full.height - meniscus;
      path.lineTo(full.left + x01 * full.width, y);
    }
    path
      ..lineTo(full.right + 2, bottom + 2)
      ..close();
    return path;
  }
}
