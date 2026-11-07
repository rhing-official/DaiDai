import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daidai/features/admin/icon_crop_dialog.dart';
import 'package:daidai/models/profile_card.dart';

void main() {
  test('既定の構図は短辺に合わせて中央を覆う', () {
    final r = iconCropDestRect(
      image: const Size(400, 200),
      focal: ImageFocal.center,
      size: 100,
    );
    expect(r.height, 100);
    expect(r.width, 200);
    expect(r.left, -50);
  });

  test('拡大しても枠(0..size)を常に覆う', () {
    final r = iconCropDestRect(
      image: const Size(300, 300),
      focal: const ImageFocal(dx: 1, dy: -1, scale: 2),
      size: 100,
    );
    expect(r.left <= 0 && r.right >= 100, isTrue);
    expect(r.top <= 0 && r.bottom >= 100, isTrue);
  });
}
