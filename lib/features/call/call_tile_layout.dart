import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' show RTCVideoViewObjectFit;

/// 通話の参加者タイルの1行あたりの人数（上の行から）。縦長の領域では1行最大2人で、
/// 2人=縦に2段、3人=上1・下2、4人=上下2人ずつ、奇数は先頭（上）の行を1人にする
/// （2026-10-13、スマホで横並びだと縦に細長くなるため）。横長の領域は`null`を
/// 返し、従来どおり`ceil(sqrt(n))`列のグリッドにする。
List<int>? callTileRowSizes(int count, {required bool portrait}) {
  if (!portrait || count <= 0) return null;
  if (count <= 2) return List.filled(count, 1);
  final rows = (count / 2).ceil();
  final sizes = List.filled(rows, 2);
  if (count.isOdd) sizes[0] = 1;
  return sizes;
}

/// 通話の参加者タイルの配置。与えられた領域に**スクロール無しで常に収まる**。
/// 縦長（高さ>幅）なら[callTileRowSizes]の行構成、横長なら従来のグリッド。
class CallTileGrid extends StatelessWidget {
  const CallTileGrid({required this.tiles, this.spacing = 4.0, super.key});

  final List<Widget> tiles;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final portrait = constraints.maxHeight > constraints.maxWidth;
        final rowSizes = callTileRowSizes(tiles.length, portrait: portrait);
        if (rowSizes != null) {
          var index = 0;
          return Padding(
            padding: EdgeInsets.all(spacing),
            child: Column(
              children: [
                for (var r = 0; r < rowSizes.length; r++) ...[
                  if (r > 0) SizedBox(height: spacing),
                  Expanded(
                    child: Row(
                      children: [
                        for (var c = 0; c < rowSizes[r]; c++) ...[
                          if (c > 0) SizedBox(width: spacing),
                          Expanded(child: tiles[index++]),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
          );
        }
        // `GridView.count`は`childAspectRatio`未指定だと正方形タイルになり、
        // 横長の領域では縦の表示可能領域を超えてスクロールを要求してしまう。
        // 制約から`childAspectRatio`を逆算して常に収める。
        final crossAxisCount = math.max(1, math.sqrt(tiles.length).ceil());
        final rowCount = math.max(1, (tiles.length / crossAxisCount).ceil());
        final tileWidth =
            (constraints.maxWidth - spacing * (crossAxisCount + 1)) /
            crossAxisCount;
        final tileHeight =
            (constraints.maxHeight - spacing * (rowCount + 1)) / rowCount;
        return GridView.count(
          crossAxisCount: crossAxisCount,
          childAspectRatio: tileWidth / tileHeight,
          padding: EdgeInsets.all(spacing),
          mainAxisSpacing: spacing,
          crossAxisSpacing: spacing,
          children: tiles,
        );
      },
    );
  }
}

/// 1対1の映像の収め方（2026-10-30）。メイン映像は、領域が縦長（高さ>幅）なら
/// 画面いっぱいに切り抜いて（Cover）埋め、横長なら全体を見せる（Contain、余白は
/// 灰色）。縦長の画面に、相手のPCカメラのような横長の映像をContainで入れると、
/// 中央に横長の帯だけが映り上下が空くため。コーナーの小窓は常にCover。
RTCVideoViewObjectFit callVideoFitFor({
  required bool portraitArea,
  required bool main,
}) => (main && !portraitArea)
    ? RTCVideoViewObjectFit.RTCVideoViewObjectFitContain
    : RTCVideoViewObjectFit.RTCVideoViewObjectFitCover;

/// 発声中の参加者のタイルを囲む緑の枠（2026-10-31）。タップは下のタイルへ通す。
const kCallTileRadius = 12.0;

class SpeakingFrame extends StatelessWidget {
  const SpeakingFrame({super.key});

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(kCallTileRadius),
        border: Border.all(color: const Color(0xFF2ECC71), width: 4),
      ),
    ),
  );
}

/// 名前・ミュートなどのラベルの下に敷く黒の半透明のシート（2026-10-31、映像の上でも
/// 読めるようにする）。影は使わない。
class CallLabelSheet extends StatelessWidget {
  const CallLabelSheet({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: child,
    ),
  );
}
