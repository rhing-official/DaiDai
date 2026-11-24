import 'package:daidai/features/call/call_tile_layout.dart';
import 'package:daidai/features/call/call_zoom_provider.dart';
import 'package:daidai/features/call/swipe_down_dock.dart';
import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

RTCVideoValue _v(int w, int h) =>
    RTCVideoValue(width: w.toDouble(), height: h.toDouble());

void main() {
  const size = Size(400, 300);
  swipeTests();

  group('callVideoContentRect', () {
    test('大きさ不明は枠いっぱい', () {
      expect(
        callVideoContentRect(RTCVideoValue.empty, size, contain: true),
        Offset.zero & size,
      );
    });
    test('縦長は左右に帯（中央に収まる）', () {
      final r = callVideoContentRect(_v(300, 600), size, contain: false);
      expect(r.height, 300);
      expect(r.width, 150);
      expect(r.center, const Offset(200, 150));
    });
    test('横長の切り抜き表示は枠いっぱい、全体表示は上下に帯', () {
      expect(
        callVideoContentRect(_v(1600, 900), size, contain: false),
        Offset.zero & size,
      );
      final r = callVideoContentRect(_v(1600, 900), size, contain: true);
      expect(r.width, 400);
      expect(r.height, 225);
    });
  });

  test('基準点は映像の矩形の内側へ寄る', () {
    const rect = Rect.fromLTWH(125, 0, 150, 300);
    expect(clampFocalToRect(const Offset(10, 50), rect), const Offset(125, 50));
    expect(
      clampFocalToRect(const Offset(390, 400), rect),
      const Offset(275, 300),
    );
  });

  group('clampZoomOffset', () {
    const content = Rect.fromLTWH(125, 0, 150, 300);
    test('まだ小さい軸は中央に固定', () {
      // 2倍で幅300 < 400: 横は中央（帯は残る）、縦は300*2=600>300で動かせる。
      final o = clampZoomOffset(const Offset(-999, -999), 2, content, size);
      expect(o.dx, (400 - 300) / 2 - 125 * 2);
      expect(o.dy, 300 - 300 * 2);
    });
    test('大きくなったら映像の端で止まる（帯が見えない）', () {
      // 4倍: 幅600 > 400。
      final min = clampZoomOffset(const Offset(-9999, 0), 4, content, size);
      final max = clampZoomOffset(const Offset(9999, 0), 4, content, size);
      expect(min.dx, 400 - 275 * 4);
      expect(max.dx, -125 * 4);
    });
    test('等倍は動かない', () {
      expect(
        clampZoomOffset(const Offset(30, 30), 1, content, size),
        Offset.zero,
      );
    });
  });
}

class _Probe extends StatelessWidget {
  const _Probe();
  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

Widget _dock(VoidCallback onDock, {Widget child = const _Probe()}) =>
    MaterialApp(
      home: Scaffold(
        body: SwipeDownDock(onDock: onDock, bottomReserve: 0, child: child),
      ),
    );

void swipeTests() {
  testWidgets('1本の下スワイプはミニ表示', (t) async {
    var docked = 0;
    await t.pumpWidget(_dock(() => docked++));
    final g = await t.startGesture(const Offset(200, 100));
    await g.moveBy(const Offset(0, 120));
    await g.up();
    expect(docked, 1);
  });

  testWidgets('2本目の指が触れたら、残った指が下へ動いてもミニ表示にならない', (t) async {
    var docked = 0;
    await t.pumpWidget(_dock(() => docked++));
    final a = await t.startGesture(const Offset(200, 100));
    final b = await t.startGesture(const Offset(260, 100));
    await b.up();
    await a.moveBy(const Offset(0, 120));
    await a.up();
    expect(docked, 0);
    // 全部離れたら、次の操作は有効。
    final c = await t.startGesture(const Offset(200, 100));
    await c.moveBy(const Offset(0, 120));
    await c.up();
    expect(docked, 1);
  });

  testWidgets('cancel()した操作はミニ表示にならない', (t) async {
    var docked = 0;
    await t.pumpWidget(
      _dock(
        () => docked++,
        child: Builder(
          builder: (context) => Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (_) => SwipeDownDockGuard.maybeOf(context)?.cancel(),
            child: const _Probe(),
          ),
        ),
      ),
    );
    final g = await t.startGesture(const Offset(200, 100));
    await g.moveBy(const Offset(0, 120));
    await g.up();
    expect(docked, 0);
  });

  testWidgets('PiP小窓のように、パンの更新でcancel()する面を動かしてもミニ表示にならない', (t) async {
    var docked = 0;
    await t.pumpWidget(
      _dock(
        () => docked++,
        child: Builder(
          builder: (context) => Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 120,
              height: 160,
              child: GestureDetector(
                dragStartBehavior: DragStartBehavior.down,
                onPanUpdate: (_) =>
                    SwipeDownDockGuard.maybeOf(context)?.cancel(),
                child: const ColoredBox(color: Colors.black),
              ),
            ),
          ),
        ),
      ),
    );
    // 小窓の上で真下へ動かしても、ミニ表示にならない。
    final inside = await t.startGesture(const Offset(60, 40));
    await inside.moveBy(const Offset(0, 120));
    await inside.up();
    expect(docked, 0);
    // 小窓の外の真下への動きは、これまでどおりミニ表示になる（操作が混ざらない）。
    final outside = await t.startGesture(const Offset(400, 100));
    await outside.moveBy(const Offset(0, 120));
    await outside.up();
    expect(docked, 1);
  });

  test('拡縮の保持は枠の大きさの比で戻る', () {
    final e = CallZoomEntry.of(
      3,
      const Offset(-100, -60),
      const Size(400, 300),
    );
    expect(e.offsetFor(const Size(200, 150)), const Offset(-50, -30));
  });
}
