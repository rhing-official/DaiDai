import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import 'keyboard_stable_body.dart';

/// メッセージ一覧の上下を、アルファマスクで透明へ溶かす（2026-11-27）。
///
/// 背景色を重ねる方式は使わない（背景が単色・ガラスのぼかし・画像のどれでも破綻しない為）。
/// 全UIスタイルで同じ見た目になる。
///
/// - 上端: 一覧の上から[topClear]までは完全に透明。そこから[topFade]かけて不透明へ。
///   [topClear]は、上部バーの裏（メッセージを見せない範囲）の高さ。
/// - 入力欄: 入力欄の上端（下から[boxTopFromBottom]の位置）の[boxFade]手前から薄くなり、
///   上端で完全に透明になる。上端から下は、一覧の下端まで全て透明（箱の左右・下の余白にも、
///   メッセージは見えない）。マスクは縦方向だけの1本のグラデーションで、画像や追加の
///   描画層は使わない。
/// - 一番古い側まで読み切って止まっている時は、上端のフェード幅を0へ滑らかに減らし、
///   端のメッセージまではっきり見せる（[lastIndex]・[positions]・[topRestInset]）。
class ChatEdgeFade extends StatelessWidget {
  const ChatEdgeFade({
    required this.child,
    required this.topClear,
    this.boxTopFromBottom = 0,
    this.boxFade = defaultBoxFade,
    this.topFade = defaultFadeExtent,
    this.positions,
    this.lastIndex,
    this.topRestInset = 0,
    super.key,
  });

  final Widget child;

  /// 上端から、完全に透明にする高さ。
  final double topClear;

  /// 入力欄の上端の位置（一覧の下端から測る）。0なら入力欄は無く、下端はフェードしない。
  final double boxTopFromBottom;

  /// 入力欄の上端へ向けて薄くなる長さ。
  final double boxFade;

  /// 上端のフェード幅（[topClear]の下から）。
  final double topFade;

  /// 一覧のアイテム位置。[lastIndex]と合わせて、一番古い側の端に着いたかを調べる。
  final ValueListenable<Iterable<ItemPosition>>? positions;

  /// 画面上で一番上（一番古い）のアイテムの番号。reverse:trueの一覧では最後の番号。
  final int? lastIndex;

  /// 一番古いアイテムが、止まった時に一覧の上端から離れる高さ（上余白）。
  final double topRestInset;

  /// 既定のフェード幅。メッセージ1行分に少し足した大きさ。
  static const double defaultFadeExtent = 32;

  /// 入力欄の上端へ向けたフェードの既定の長さ。一番新しいメッセージが止まった時に薄く
  /// ならないよう、一覧の下余白にも、この長さを足すこと。
  static const double defaultBoxFade = 24;

  /// 端から離れ始めて、フェードが全幅になるまでの距離。
  static const double _edgeRamp = 24;

  /// 一番古いアイテムの上端が、止まった位置から[offset]だけ上へ動いた時の、
  /// 上端フェードの強さ（0〜1）。止まっている時は0。
  @visibleForTesting
  static double topStrength(double offset) =>
      (offset / _edgeRamp).clamp(0.0, 1.0);

  /// 一覧の高さ[height]・各長さから、マスクの色の並びと位置を作る。
  /// 位置は0〜1の割合で、単調に増える。
  @visibleForTesting
  static ({List<double> alphas, List<double> stops}) buildMask({
    required double height,
    required double topClear,
    required double topFade,
    double boxTopFromBottom = 0,
    double boxFade = defaultBoxFade,
  }) {
    if (height <= 0) {
      return (alphas: const [1.0, 1.0], stops: const [0.0, 1.0]);
    }
    final clear = topClear.clamp(0.0, height);
    final top = math.min(topFade.clamp(0.0, height), height - clear);
    final topEnd = clear + top;

    final alphas = <double>[];
    final stops = <double>[];
    void add(double y, double alpha) {
      final t = (y / height).clamp(0.0, 1.0);
      if (stops.isNotEmpty && t < stops.last) return;
      stops.add(t);
      alphas.add(alpha);
    }

    // なだらかに見えるよう、滑らかな曲線（smoothstep）を段に刻む。
    const steps = 8;
    add(0, 0);
    add(clear, 0);
    if (top > 0) {
      for (var i = 1; i <= steps; i++) {
        final u = i / steps;
        add(clear + top * u, u * u * (3 - 2 * u));
      }
    } else {
      add(clear, 1);
    }
    if (boxTopFromBottom > 0) {
      // 入力欄の上端で完全に透明。そこから下は、下端まで透明のまま。
      final boxTop = (height - boxTopFromBottom).clamp(topEnd, height);
      final boxStart = math.max(boxTop - boxFade, topEnd);
      add(boxStart, 1);
      if (boxTop > boxStart) {
        for (var i = 1; i <= steps; i++) {
          final u = i / steps;
          add(boxStart + (boxTop - boxStart) * u, 1 - u * u * (3 - 2 * u));
        }
      } else {
        add(boxTop, 0);
      }
      add(height, 0);
    } else {
      add(height, 1);
    }
    return (alphas: alphas, stops: stops);
  }

  @override
  Widget build(BuildContext context) {
    // キーボード・ぺったんドックで本体全体が上へずれている間は、ずれた分だけ透明な範囲を
    // 広げる（上部バーの裏へ上がったメッセージを、硬い切り口ではなくフェードで消す）。
    final shift = KeyboardShiftScope.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        Widget masked(double strength) {
          final mask = buildMask(
            height: height,
            topClear: topClear + shift,
            topFade: topFade * strength,
            boxTopFromBottom: boxTopFromBottom,
            boxFade: boxFade,
          );
          // 位置の割合は単調に増える。同じ位置が続いても良い。
          return ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (bounds) => LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [for (final a in mask.alphas) Color.fromRGBO(0, 0, 0, a)],
              stops: mask.stops,
            ).createShader(bounds),
            child: child,
          );
        }

        final listenable = positions;
        final last = lastIndex;
        if (listenable == null || last == null || height <= 0) {
          return masked(1);
        }
        return ValueListenableBuilder<Iterable<ItemPosition>>(
          valueListenable: listenable,
          builder: (context, items, _) {
            ItemPosition? oldest;
            for (final p in items) {
              if (p.index == last) {
                oldest = p;
                break;
              }
            }
            // 一番古いアイテムが見えていない間は、常に全幅。見えている時は、止まった
            // 位置からどれだけ上へ動いたかで、0から全幅へ。
            final strength = oldest == null
                ? 1.0
                : topStrength(
                    topRestInset - (1 - oldest.itemTrailingEdge) * height,
                  );
            return masked(strength);
          },
        );
      },
    );
  }
}
