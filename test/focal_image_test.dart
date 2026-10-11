import 'package:daidai/models/profile_card.dart';
import 'package:daidai/widgets/focal_image.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ImageFocal', () {
    test('JSONの往復と、範囲外・不正値のクランプ/フォールバック', () {
      const focal = ImageFocal(dx: 0.5, dy: -0.25, scale: 2);
      expect(ImageFocal.fromJson(focal.toJson()), focal);
      final clamped = ImageFocal.fromJson({'dx': 5, 'dy': -9, 'scale': 99})!;
      expect(clamped.dx, 1);
      expect(clamped.dy, -1);
      expect(clamped.scale, kMaxImageFocalScale);
      expect(ImageFocal.fromJson({'dx': 'x'})!.isDefault, isTrue);
      expect(ImageFocal.fromJson(null), isNull);
    });

    test('ProfileCard: 既存データ（キー無し）は位置nullで読め、既定のままならキーを出さない', () {
      final legacy = ProfileCard.fromJson({'id': 'c', 'name': 'n'});
      expect(legacy.backgroundFocal, isNull);
      expect(legacy.toJson().containsKey('backgroundFocal'), isFalse);
      final card = legacy.copyWith(
        iconFocal: const ImageFocal(dx: 1, scale: 1.5),
      );
      final restored = ProfileCard.fromJson(card.toJson());
      expect(restored.iconFocal, const ImageFocal(dx: 1, scale: 1.5));
      expect(restored.copyWith(clearIconFocal: true).iconFocal, isNull);
    });
  });

  group('focalImageRect', () {
    const box = Size(100, 100);
    const wide = Size(400, 200); // 横長 → coverで高さに合わせ幅が余る

    test('既定（中央・等倍）は従来のcover中央と同じ', () {
      final rect = focalImageRect(
        box: box,
        image: wide,
        focal: ImageFocal.center,
      );
      expect(rect.size, const Size(200, 100));
      expect(rect.left, -50);
      expect(rect.top, 0);
    });

    test('dx=-1で画像の左端、dx=1で右端がボックスに揃う', () {
      expect(
        focalImageRect(
          box: box,
          image: wide,
          focal: const ImageFocal(dx: -1),
        ).left,
        0,
      );
      expect(
        focalImageRect(
          box: box,
          image: wide,
          focal: const ImageFocal(dx: 1),
        ).right,
        100,
      );
    });

    test('拡大率を上げると描画サイズが比例して大きくなる', () {
      final rect = focalImageRect(
        box: box,
        image: wide,
        focal: const ImageFocal(scale: 2),
      );
      expect(rect.size, const Size(400, 200));
    });
  });

  group('focalAfterGesture', () {
    const box = Size(100, 100);
    const wide = Size(400, 200);

    test('右へドラッグすると画像が指と同じ量だけ右へ動く（余りのある軸のみ）', () {
      final next = focalAfterGesture(
        focal: ImageFocal.center,
        box: box,
        image: wide,
        delta: const Offset(10, 7),
      );
      final rect = focalImageRect(box: box, image: wide, focal: next);
      expect(rect.left, closeTo(-50 + 10, 0.001));
      // 縦は余りが無い（cover）ので動かない。
      expect(next.dy, 0);
    });

    test('端を超えてドラッグしても位置は範囲内にクランプされる', () {
      final next = focalAfterGesture(
        focal: ImageFocal.center,
        box: box,
        image: wide,
        delta: const Offset(9999, 0),
      );
      expect(next.dx, -1);
    });

    test('ピンチで拡大率が変わり、上限・下限でクランプされる', () {
      final zoomed = focalAfterGesture(
        focal: ImageFocal.center,
        box: box,
        image: wide,
        scaleFactor: 100,
      );
      expect(zoomed.scale, kMaxImageFocalScale);
      final shrunk = focalAfterGesture(
        focal: zoomed,
        box: box,
        image: wide,
        scaleFactor: 0.0001,
      );
      expect(shrunk.scale, 1);
    });
  });
}
