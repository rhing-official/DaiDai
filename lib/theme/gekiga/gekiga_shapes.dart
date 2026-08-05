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

/// [vertices]の多角形の各頂点を、隣接する2辺それぞれの方向に沿って
/// [cut]だけ離れた2点に置き換え、角を斜めにカットした（面取りした）
/// 多角形の頂点リストを返す（矩形の4頂点なら8頂点の八角形風になる）。
/// [handDrawnPolygonPath]・[insetPolygon]は頂点数を問わない汎用実装のため、
/// この関数で頂点を増やしてから渡すだけで、ジグザグ描画・同心オフセットの
/// どちらもそのまま角カット済みの形に対応する（2026-08-05追加）。
List<Offset> cutCorners(List<Offset> vertices, double cut) {
  final n = vertices.length;
  final result = <Offset>[];
  for (var i = 0; i < n; i++) {
    final curr = vertices[i];
    final prev = vertices[(i - 1 + n) % n];
    final next = vertices[(i + 1) % n];
    final toPrev = prev - curr;
    final toNext = next - curr;
    result.add(curr + toPrev / toPrev.distance * cut);
    result.add(curr + toNext / toNext.distance * cut);
  }
  return result;
}

/// 劇画UI「モノクロボックス」共通の不規則四角形の頂点（左上が外側へ
/// 突き出た鋭角、右上・右下・左下は直角付近〜鈍角、という非対称な形）。
/// メッセージ画面アイコン（`GekigaPhotoFrame`）で最初に採用した形を、
/// ボックス系ウィジェット全体の共通言語として抽出したもの（2026-08-05、
/// 旧「ギザギザボックス」＝手描き風ジグザグ角カットの後継。手描きジグザグ
/// は廃止し、直線のみで構成する）。
///
/// [topLeft]/[topRight]/[bottomRight]/[bottomLeft]でどの角に非対称な形を
/// 適用するかを選べる（一覧の接合箱で、隣の箱と接する側は直角のまま
/// 残したい場合にfalseにする）。[overflow]は[topLeft]がtrueの時のみ
/// 効果を持ち、左上角を矩形の外（左・上方向）へその分だけ突き出させる
/// （呼び出し側は`Positioned(left: -overflow, top: -overflow, width:
/// width+overflow, height: height+overflow)`と`Stack(clipBehavior:
/// Clip.none)`を組み合わせて描画領域を確保する必要がある。[topLeft]が
/// falseの場合や接合箱側では[overflow]は無視される）。
/// モノクロボックスの左上角を突き出させる標準の比率（`size`に対する比率）。
/// 単体の箱（バッジ・アイコンボタン・テキスト欄・接合していない単独の
/// リスト項目）で共通して使う。
const monochromeBoxOverflowRatio = 0.15;

List<Offset> monochromeBoxVertices(
  double width,
  double height, {
  double overflow = 0,
  bool topLeft = true,
  bool topRight = true,
  bool bottomRight = true,
  bool bottomLeft = true,
}) {
  final o = topLeft ? overflow : 0.0;
  // 左上角の突き出しはx方向のみ[overflow]分残し、y方向の突き出しは0にする
  // （2026-08-05調整、前回はy方向を半分に抑えるだけだったが変化が乏しかった
  // ため無しまで戻した）。左上角自身の鋭さを右下寄りに戻すと同時に、
  // 左下角の内角がその分だけ自動的に大きくなる（両者は左下↔左上の辺を
  // 共有しており、この辺の傾きが変わるため）。x方向まで縮めると逆に左下角
  // の内角は小さくなってしまうため、x方向は変えずy方向だけを縮めている。
  final topLeftY = 0.0;
  return [
    topLeft ? Offset(-o, -topLeftY) : Offset(o, o),
    topRight
        ? Offset(width * 0.90 + o, height * 0.05 + o)
        : Offset(width + o, o),
    bottomRight
        ? Offset(width * 0.90 + o, height * 0.85 + o)
        : Offset(width + o, height + o),
    bottomLeft ? Offset(width * 0.07 + o, height + o) : Offset(o, height + o),
  ];
}

Path pathFromPoints(List<Offset> points) {
  final path = Path()..moveTo(points.first.dx, points.first.dy);
  for (final p in points.skip(1)) {
    path.lineTo(p.dx, p.dy);
  }
  path.close();
  return path;
}

/// [from]から[to]までの1辺だけを、手描き風に少しだけジグザグに揺らした
/// 開いた点列（[from]自体は含まない、[to]で終わる）にする。[seed]・
/// [from]/[to]が同じなら常に同じ点列になる。
///
/// 隣り合う2つの箱の接する辺を同じ1本の線として共有するために
/// 使う（[GekigaJointedTileList]・[GekigaJointedPair]参照、2026-08-04
/// 追加。[handDrawnPolygonPath]は必ず閉多角形を返すため1辺だけを
/// 取り出せず、そのロジックをここに抜き出した）。
List<Offset> jitteredEdgePoints(
  Offset from,
  Offset to,
  int seed, {
  double jitter = 3,
  int segments = 4,
}) {
  final random = math.Random(seed);
  final points = <Offset>[];
  for (var s = 1; s <= segments; s++) {
    final t = s / segments;
    final base = Offset.lerp(from, to, t)!;
    points.add(
      Offset(
        base.dx + (random.nextDouble() - 0.5) * 2 * jitter,
        base.dy + (random.nextDouble() - 0.5) * 2 * jitter,
      ),
    );
  }
  return points;
}

/// [vertices]で囲まれた多角形の各辺を、手描き風に少しだけジグザグに揺らした
/// 閉じたPathを作る。[seed]が同じなら常に同じ形になる（メッセージID・
/// ユーザーIDのhashCodeを渡すことで、再描画のたびに形がガタつかないように
/// している）。（2026-07-30、chat_screen.dartの`_handDrawnPolygonPath`から
/// 移動・公開化。2026-08-04、各辺の生成を[jitteredEdgePoints]に委譲する
/// 形にリファクタ）
Path handDrawnPolygonPath(
  List<Offset> vertices,
  int seed, {
  double jitter = 3,
  int segmentsPerEdge = 4,
}) {
  final random = math.Random(seed);
  final points = <Offset>[
    for (var i = 0; i < vertices.length; i++)
      ...jitteredEdgePoints(
        vertices[i],
        vertices[(i + 1) % vertices.length],
        // Web（dart2js/DDC）ではintがJSのdoubleとして扱われ、32bit符号付き
        // 整数の範囲を超えるnextIntの引数（元は`1 << 32`）で不正な値を返す
        // 場合があり、それがOffsetに混入してPathが描画されなくなる不具合の
        // 原因になっていた（2026-08-04発覚・修正。ネイティブ実行の
        // `flutter test`では再現しないため見つかりにくい）。全プラットフォーム
        // で安全な32bit符号付き整数の最大値に収める。
        random.nextInt(0x7fffffff),
        jitter: jitter,
        segments: segmentsPerEdge,
      ),
  ];
  return pathFromPoints(points);
}
