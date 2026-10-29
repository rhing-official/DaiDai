import 'package:daidai/features/chat/sticker_picker_dock.dart';
import 'package:daidai/providers/recent_stickers_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('addRecentSticker', () {
    test('新しいものを先頭へ、重複は先頭へ移動する', () {
      expect(addRecentSticker(['a', 'b'], 'c'), ['c', 'a', 'b']);
      expect(addRecentSticker(['a', 'b', 'c'], 'b'), ['b', 'a', 'c']);
    });

    test('上限を超えた古いものは落とす', () {
      final ids = [for (var i = 0; i < kRecentStickerLimit; i++) 'id$i'];
      final next = addRecentSticker(ids, 'new');
      expect(next.length, kRecentStickerLimit);
      expect(next.first, 'new');
      expect(next.contains('id${kRecentStickerLimit - 1}'), isFalse);
    });
  });

  group('StickerPickerDock.snap', () {
    const screen = 800.0;
    final half = StickerPickerDock.halfHeight(screen);
    final expanded = StickerPickerDock.expandedHeight(screen);

    test('速い上スワイプは拡大、速い下スワイプは縮小', () {
      expect(
        StickerPickerDock.snap(
          height: half,
          velocity: -1500,
          screenHeight: screen,
        ),
        StickerDockStage.expanded,
      );
      expect(
        StickerPickerDock.snap(
          height: half,
          velocity: 1500,
          screenHeight: screen,
        ),
        StickerDockStage.closed,
      );
      expect(
        StickerPickerDock.snap(
          height: expanded,
          velocity: 1500,
          screenHeight: screen,
        ),
        StickerDockStage.half,
      );
    });

    test('ゆっくり離した時は最寄りの段', () {
      expect(
        StickerPickerDock.snap(height: 20, velocity: 0, screenHeight: screen),
        StickerDockStage.closed,
      );
      expect(
        StickerPickerDock.snap(
          height: half + 30,
          velocity: 0,
          screenHeight: screen,
        ),
        StickerDockStage.half,
      );
      expect(
        StickerPickerDock.snap(
          height: expanded - 30,
          velocity: 0,
          screenHeight: screen,
        ),
        StickerDockStage.expanded,
      );
    });
  });
}
