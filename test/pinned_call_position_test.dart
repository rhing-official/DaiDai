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

  group('pinnedCallOffsetForPointer（ポインターへの絶対追従）', () {
    test('掴んだ位置を保ったまま、ポインターに完全に追従する', () {
      // 左上(100,200)の箱の(30,40)を掴んだ → grab=(30,40)。
      const grab = Offset(30, 40);
      expect(
        pinnedCallOffsetForPointer(
          pointer: const Offset(130, 240),
          grab: grab,
          screen: screen,
          topInset: 24,
        ),
        const Offset(100, 200),
      );
      // 途中のイベントを飛ばしても、最後のポインター位置だけで決まる
      // （相対移動の積算ではないので取りこぼしが起きない）。
      expect(
        pinnedCallOffsetForPointer(
          pointer: const Offset(280, 440),
          grab: grab,
          screen: screen,
          topInset: 24,
        ),
        const Offset(250, 400),
      );
    });

    test('端まで動かしても画面内に収まり、戻せばすぐ追従する', () {
      const grab = Offset(30, 40);
      expect(
        pinnedCallOffsetForPointer(
          pointer: const Offset(999, 999),
          grab: grab,
          screen: screen,
          topInset: 24,
        ),
        Offset(400 - 140, 800 - 200),
      );
      expect(
        pinnedCallOffsetForPointer(
          pointer: const Offset(130, 240),
          grab: grab,
          screen: screen,
          topInset: 24,
        ),
        const Offset(100, 200),
      );
    });
  });
}
