import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daidai/widgets/focal_image.dart';

Future<MemoryImage> _png(int alpha) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    const ui.Rect.fromLTWH(0, 0, 4, 4),
    ui.Paint()..color = ui.Color.fromARGB(alpha, 255, 0, 0),
  );
  final image = await recorder.endRecording().toImage(4, 4);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return MemoryImage(Uint8List.view(data!.buffer));
}

void main() {
  testWidgets('透けている画素があるときだけtrue', (tester) async {
    await tester.runAsync(() async {
      expect(await resolveImageHasAlpha(await _png(128)), isTrue);
      expect(await resolveImageHasAlpha(await _png(255)), isFalse);
    });
  });
}
