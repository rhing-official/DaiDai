import 'package:flutter/material.dart';

import '../../theme/gekiga/gekiga_colors.dart';
import 'gekiga_panel_box.dart' show kGekigaBoxThicknessBase;
import 'monochrome_box.dart';

/// 劇画の長方形の箱（ギザギザの太線）。中身の大きさに合わせて枠を描く
/// （`GekigaBadgeShape`は正方形で描くため、横長・縦長の箱には使えない、2026-11-10）。
/// ポップアップ・メニューの外枠に使う。
class GekigaRectBox extends StatelessWidget {
  const GekigaRectBox({required this.child, this.seed = 0, super.key});

  final Widget child;
  final int seed;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size = constraints.biggest;
              return CustomPaint(
                painter: MonochromeBoxPainter(
                  vertices: [
                    Offset.zero,
                    Offset(size.width, 0),
                    Offset(size.width, size.height),
                    Offset(0, size.height),
                  ],
                  thicknessBase: kGekigaBoxThicknessBase,
                  fillColor: GekigaColors.panel,
                  seed: seed,
                ),
              );
            },
          ),
        ),
        child,
      ],
    );
  }
}
