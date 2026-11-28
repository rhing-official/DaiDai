import 'dart:ui' as ui;

import 'package:daidai/providers/nav_chip_band_provider.dart';
import 'package:daidai/widgets/nav_chip_halo.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 全面が不透明な赤の部品に、チップの帯の滲みを掛けて、画素のアルファを読む。
Future<List<int>> _alphas(
  WidgetTester tester, {
  required Rect? band,
  bool enabled = true,
  required List<Offset> points,
}) async {
  final key = GlobalKey();
  final container = ProviderContainer();
  addTearDown(container.dispose);
  container.read(navChipBandRectProvider.notifier).set(band);
  await tester.binding.setSurfaceSize(const Size(300, 300));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: RepaintBoundary(
          key: key,
          child: NavChipHalo(
            enabled: enabled,
            child: const ColoredBox(
              color: Color(0xFFFF0000),
              child: SizedBox.expand(),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  late List<int> result;
  await tester.runAsync(() async {
    final b = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final img = await b.toImage(pixelRatio: 1);
    final d = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    result = [
      for (final p in points)
        d.getUint8(((p.dy.toInt() * img.width) + p.dx.toInt()) * 4 + 3),
    ];
  });
  return result;
}

void main() {
  const band = Rect.fromLTWH(60, 220, 160, 56);

  testWidgets('チップの帯の中は透明に近く、離れた所は不透明のまま', (tester) async {
    final a = await _alphas(
      tester,
      band: band,
      points: const [Offset(140, 248), Offset(140, 120), Offset(10, 10)],
    );
    expect(a[0], lessThan(30), reason: '帯の中が抜けていない');
    expect(a[1], 255, reason: '離れた所まで薄くなっている');
    expect(a[2], 255);
  });

  testWidgets('縁は、なだらかに薄くなる（途中のアルファが有る）', (tester) async {
    final a = await _alphas(
      tester,
      band: band,
      points: [for (var y = 180; y <= 220; y += 5) Offset(140, y.toDouble())],
    );
    expect(a.first, greaterThan(a.last));
    expect(a.any((v) => v > 20 && v < 235), isTrue, reason: '途中の段階が無い');
  });

  testWidgets('帯が無い・無効の時は、何も変えない', (tester) async {
    expect(
      await _alphas(tester, band: null, points: const [Offset(140, 248)]),
      [255],
    );
    expect(
      await _alphas(
        tester,
        band: band,
        enabled: false,
        points: const [Offset(140, 248)],
      ),
      [255],
    );
  });
}
