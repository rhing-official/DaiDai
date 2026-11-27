import 'dart:ui';

import 'package:daidai/widgets/liquid_tile_group.dart';
import 'package:flutter_test/flutter_test.dart';

/// 劇画の箱の塗りを、描きの進み具合に合わせて描く窓口（`DrawReveal`、2026-11-27）。
void main() {
  Canvas newCanvas() => Canvas(PictureRecorder());

  int paintCount(DrawReveal reveal, int index, {required bool selected}) {
    var count = 0;
    reveal.paintRevealed(
      newCanvas(),
      index,
      const Size(100, 40),
      selected,
      () => count++,
    );
    return count;
  }

  test('知らせが無い箱は、選ばれているかどうかで決める（従来どおり即時）', () {
    final reveal = DrawReveal(TileDrawProgress());
    expect(paintCount(reveal, 0, selected: true), 1);
    expect(paintCount(reveal, 0, selected: false), 0);
  });

  test('進み具合が0の箱は、選ばれていても描かない（まだ塗っていない）', () {
    final progress = TileDrawProgress()..set(0, 0);
    expect(paintCount(DrawReveal(progress), 0, selected: true), 0);
  });

  test('進み具合が1の箱は、全体を選ばれた形にする', () {
    final progress = TileDrawProgress()..set(0, 1);
    expect(paintCount(DrawReveal(progress), 0, selected: false), 1);
  });

  test('途中の箱は、選ばれた形を1回だけ描く（ペンで塗った所だけ残す）', () {
    final progress = TileDrawProgress()..set(0, 0.5);
    expect(paintCount(DrawReveal(progress), 0, selected: true), 1);
  });

  test('知らせると通知され、項目が無くなると既定へ戻る', () {
    final progress = TileDrawProgress();
    var notified = 0;
    progress.addListener(() => notified++);
    progress.set(2, 0.3);
    expect(notified, 1);
    progress.set(2, 0.3); // 変化なし
    expect(notified, 1);
    expect(progress.valueOf(2), 0.3);
    progress.remove(2);
    expect(progress.valueOf(2), isNull);
  });
}
