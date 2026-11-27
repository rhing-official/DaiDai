import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:daidai/theme/chalk/chalk_paint.dart';

/// 再発防止（2026-11-27）。チョークの塗りの粉の抜けが、アイコンの上にも出ると、描き直した白い
/// アイコンが部分的に透けて、灰色（クリーム色）に見えた。アイコンの範囲には、抜けを作らない。
void main() {
  test('粉の抜けは、アイコンの範囲を除いて作る', () async {
    const size = 120.0;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.saveLayer(const ui.Rect.fromLTWH(0, 0, size, size), ui.Paint());
    canvas.drawRect(
      const ui.Rect.fromLTWH(0, 0, size, size),
      ui.Paint()..color = const ui.Color(0xFFFFFFFF),
    );
    const keep = ui.Rect.fromLTWH(40, 40, 40, 40);
    ChalkPaint.punchGrainExcept(
      canvas,
      const ui.Rect.fromLTWH(0, 0, size, size),
      [keep],
    );
    canvas.restore();
    final image = await recorder.endRecording().toImage(
      size.toInt(),
      size.toInt(),
    );
    final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    int alphaAt(int x, int y) => data.getUint8((y * size.toInt() + x) * 4 + 3);
    var inKeepMin = 255;
    for (var y = 40; y < 80; y++) {
      for (var x = 40; x < 80; x++) {
        if (alphaAt(x, y) < inKeepMin) inKeepMin = alphaAt(x, y);
      }
    }
    expect(inKeepMin, 255, reason: 'アイコンの範囲に、抜けが有る');
    var outsideHoles = 0;
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        final inside = x >= 40 && x < 80 && y >= 40 && y < 80;
        if (!inside && alphaAt(x, y) < 255) outsideHoles++;
      }
    }
    expect(outsideHoles, greaterThan(0), reason: '範囲の外には、抜けが有る');
  });
}
