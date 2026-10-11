import 'dart:ui';

import 'package:daidai/features/call/pinned_call_position.dart';
import 'package:flutter_test/flutter_test.dart';

// 通話ミニ表示のドラッグ位置の補正（2026-10-12）。
void main() {
  const screen = Size(400, 800);

  test('未指定なら右上（上端のセーフエリア分と余白を空ける）', () {
    final offset = clampPinnedCallOffset(
      offset: null,
      screen: screen,
      topInset: 24,
    );
    expect(offset, Offset(400 - 140 - 8, 24 + 8));
  });

  test('画面外へはみ出す位置は画面内に収める', () {
    expect(
      clampPinnedCallOffset(
        offset: const Offset(-50, -50),
        screen: screen,
        topInset: 24,
      ),
      const Offset(0, 24),
    );
    expect(
      clampPinnedCallOffset(
        offset: const Offset(999, 999),
        screen: screen,
        topInset: 24,
      ),
      const Offset(400 - 140, 800 - 200),
    );
  });

  test('画面内の位置はそのまま', () {
    expect(
      clampPinnedCallOffset(
        offset: const Offset(100, 300),
        screen: screen,
        topInset: 24,
      ),
      const Offset(100, 300),
    );
  });
}
