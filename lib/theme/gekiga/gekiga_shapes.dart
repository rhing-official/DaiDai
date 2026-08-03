import 'dart:math' as math;

import 'package:flutter/material.dart';

/// [vertices]の多角形の各辺を内側へ[inset]だけ平行移動し、隣り合う辺の
/// 交点を新しい頂点として返す（同心の縁取り・塗りを重ねて描くための
/// 下ごしらえ）。重心方向へ頂点を縮める単純な方式だと、辺の向きによって
/// 縁の太さがバラついたり凹み部分で図形が破綻したりするため、辺単位の
/// 平行移動＋交点計算という、太さが均一になる正しいオフセット処理にして
/// いる（2026-07-30、chat_screen.dartの`_insetPolygon`から移動・公開化。
/// アプリ全体で劇画のジグザグ意匠を共有するための共通部品）。
List<Offset> insetPolygon(List<Offset> vertices, double inset) {
  final n = vertices.length;
  final centroid = vertices.reduce((a, b) => a + b) / n.toDouble();
  final origins = <Offset>[];
  final dirs = <Offset>[];
  for (var i = 0; i < n; i++) {
    final a = vertices[i];
    final b = vertices[(i + 1) % n];
    final edge = b - a;
    final dir = edge / edge.distance;
    var normal = Offset(-dir.dy, dir.dx);
    final mid = (a + b) / 2;
    final towardCentroid = centroid - mid;
    if (towardCentroid.dx * normal.dx + towardCentroid.dy * normal.dy < 0) {
      normal = -normal;
    }
    origins.add(a + normal * inset);
    dirs.add(dir);
  }
  final result = <Offset>[];
  for (var i = 0; i < n; i++) {
    final prev = (i - 1 + n) % n;
    final p1 = origins[prev];
    final d1 = dirs[prev];
    final p2 = origins[i];
    final d2 = dirs[i];
    final denom = d1.dx * d2.dy - d1.dy * d2.dx;
    if (denom.abs() < 1e-6) {
      result.add(p2);
      continue;
    }
    final diff = p2 - p1;
    final t = (diff.dx * d2.dy - diff.dy * d2.dx) / denom;
    result.add(p1 + d1 * t);
  }
  return result;
}

/// 劇画スタイルの自由配置ラベル（設定タブのカテゴリ一覧、フォントデザインが
/// 「劇画」のときのみ使用）用に、[seed]から決定的な回転角（ラジアン）と
/// 横方向のずれ幅を1組返す。`handDrawnPolygonPath`と同じ「文字列のhashCode等を
/// seedにした`math.Random`」パターンを踏襲し、再描画のたびに同じラベルは
/// 同じ傾き・ずれになる（2026-08-03新規）。
({double angle, double dx}) freeformLabelTilt(
  int seed, {
  double maxDegrees = 6,
  double maxDx = 14,
}) {
  final random = math.Random(seed);
  final angleDeg = (random.nextDouble() * 2 - 1) * maxDegrees;
  final dx = (random.nextDouble() * 2 - 1) * maxDx;
  return (angle: angleDeg * math.pi / 180, dx: dx);
}

Path pathFromPoints(List<Offset> points) {
  final path = Path()..moveTo(points.first.dx, points.first.dy);
  for (final p in points.skip(1)) {
    path.lineTo(p.dx, p.dy);
  }
  path.close();
  return path;
}

/// [vertices]で囲まれた多角形の各辺を、手描き風に少しだけジグザグに揺らした
/// 閉じたPathを作る。[seed]が同じなら常に同じ形になる（メッセージID・
/// ユーザーIDのhashCodeを渡すことで、再描画のたびに形がガタつかないように
/// している）。（2026-07-30、chat_screen.dartの`_handDrawnPolygonPath`から
/// 移動・公開化）
Path handDrawnPolygonPath(
  List<Offset> vertices,
  int seed, {
  double jitter = 3,
  int segmentsPerEdge = 4,
}) {
  final random = math.Random(seed);
  final points = <Offset>[];
  for (var i = 0; i < vertices.length; i++) {
    final from = vertices[i];
    final to = vertices[(i + 1) % vertices.length];
    for (var s = 1; s <= segmentsPerEdge; s++) {
      final t = s / segmentsPerEdge;
      final base = Offset.lerp(from, to, t)!;
      points.add(
        Offset(
          base.dx + (random.nextDouble() - 0.5) * 2 * jitter,
          base.dy + (random.nextDouble() - 0.5) * 2 * jitter,
        ),
      );
    }
  }
  final path = Path()..moveTo(points.first.dx, points.first.dy);
  for (final p in points.skip(1)) {
    path.lineTo(p.dx, p.dy);
  }
  path.close();
  return path;
}
