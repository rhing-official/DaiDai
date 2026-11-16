import 'package:daidai/features/call/call_tile_layout.dart';
import 'package:daidai/features/call/call_pin_provider.dart';
import 'package:daidai/l10n/app_locale.dart';
import 'package:daidai/providers/app_locale_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart'
    show RTCVideoRenderer, RTCVideoValue;
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _stage(Size size, List<String> keys, {ProviderContainer? container}) {
  final child = MaterialApp(
    home: Center(
      child: SizedBox(
        width: size.width,
        height: size.height,
        child: CallTileStage(
          specs: [
            for (final k in keys)
              CallTileSpec(
                key: k,
                build: (_) =>
                    ColoredBox(key: ValueKey('t$k'), color: Colors.grey),
              ),
          ],
        ),
      ),
    ),
  );
  return container == null
      ? ProviderScope(
          overrides: [
            initialAppLocaleProvider.overrideWithValue(AppLocale.japanese),
          ],
          child: child,
        )
      : UncontrolledProviderScope(container: container, child: child);
}

Rect _r(WidgetTester t, String k) => t.getRect(find.byKey(ValueKey('t$k')));

void main() {
  group('callTileRowSizes', () {
    test('縦長: 1=[1]、2=縦2段、奇数は最上行が1枚', () {
      final expected = {
        1: [1],
        2: [1, 1],
        3: [1, 2],
        4: [2, 2],
        5: [1, 2, 2],
        6: [2, 2, 2],
        7: [1, 2, 2, 2],
      };
      expected.forEach((n, rows) {
        expect(callTileRowSizes(n, portrait: true), rows, reason: 'n=$n');
      });
    });

    test('横長: 2=横並べ、3=上1下2、4=2×2、5=上2下3、6=上下3、9以上は1行最大4', () {
      final expected = {
        1: [1],
        2: [2],
        3: [1, 2],
        4: [2, 2],
        5: [2, 3],
        6: [3, 3],
        7: [3, 4],
        8: [4, 4],
        9: [1, 4, 4],
        10: [2, 4, 4],
        11: [3, 4, 4],
        12: [4, 4, 4],
      };
      expected.forEach((n, rows) {
        expect(callTileRowSizes(n, portrait: false), rows, reason: 'n=$n');
      });
    });

    test('0枚はnull', () {
      expect(callTileRowSizes(0, portrait: true), isNull);
      expect(callTileRowSizes(0, portrait: false), isNull);
    });
  });

  group('CallTileStage', () {
    testWidgets('縦長の2枚は縦に並ぶ', (tester) async {
      await tester.pumpWidget(_stage(const Size(300, 600), ['a', 'b']));
      expect(_r(tester, 'a').left, _r(tester, 'b').left);
      expect(_r(tester, 'a').bottom, lessThan(_r(tester, 'b').top));
    });

    testWidgets('横長の2枚は横に並ぶ', (tester) async {
      await tester.pumpWidget(_stage(const Size(600, 300), ['a', 'b']));
      expect(_r(tester, 'a').top, _r(tester, 'b').top);
      expect(_r(tester, 'a').right, lessThan(_r(tester, 'b').left));
    });

    testWidgets('横長の3枚は上1枚（下と同じ幅で中央）、下2枚', (tester) async {
      await tester.pumpWidget(_stage(const Size(600, 300), ['a', 'b', 'c']));
      final a = _r(tester, 'a');
      final b = _r(tester, 'b');
      final c = _r(tester, 'c');
      expect(a.width, closeTo(b.width, 0.5));
      expect(a.center.dx, closeTo(400, 0.5)); // 領域（600幅）の中央＝画面の中央
      expect(b.top, c.top);
      expect(a.bottom, lessThan(b.top));
    });

    testWidgets('横長の4枚は上下2枚ずつ、5枚は上2下3', (tester) async {
      await tester.pumpWidget(
        _stage(const Size(800, 400), ['a', 'b', 'c', 'd']),
      );
      expect(_r(tester, 'a').top, _r(tester, 'b').top);
      expect(_r(tester, 'c').top, _r(tester, 'd').top);
      expect(_r(tester, 'a').bottom, lessThan(_r(tester, 'c').top));
      await tester.pumpWidget(
        _stage(const Size(900, 400), ['a', 'b', 'c', 'd', 'e']),
      );
      await tester.pump();
      expect(_r(tester, 'a').top, _r(tester, 'b').top);
      expect(_r(tester, 'c').top, _r(tester, 'e').top);
      expect(_r(tester, 'b').bottom, lessThan(_r(tester, 'c').top));
    });

    testWidgets('縦長の5枚は上1枚（全幅）、その下に2枚ずつ', (tester) async {
      await tester.pumpWidget(
        _stage(const Size(300, 700), ['a', 'b', 'c', 'd', 'e']),
      );
      expect(_r(tester, 'a').width, greaterThan(_r(tester, 'b').width * 1.5));
      expect(_r(tester, 'b').top, _r(tester, 'c').top);
      expect(_r(tester, 'd').top, _r(tester, 'e').top);
    });

    testWidgets('ピン留めした枚は上の大きい部分、残りは下の帯に並ぶ', (tester) async {
      final container = ProviderContainer(
        overrides: [
          initialAppLocaleProvider.overrideWithValue(AppLocale.japanese),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        _stage(const Size(600, 400), ['a', 'b', 'c'], container: container),
      );
      await tester.tap(find.byKey(const ValueKey('pin-a')));
      await tester.pump();
      expect(container.read(callPinnedTilesProvider), {'a'});
      final a = _r(tester, 'a');
      final b = _r(tester, 'b');
      final c = _r(tester, 'c');
      expect(a.height, greaterThan(b.height * 2));
      expect(b.top, c.top);
      expect(a.bottom, lessThanOrEqualTo(b.top));
    });

    testWidgets('もう一度押すとピンが外れ、消えたウィンドウのピンは外れる', (tester) async {
      final container = ProviderContainer(
        overrides: [
          initialAppLocaleProvider.overrideWithValue(AppLocale.japanese),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        _stage(const Size(600, 400), ['a', 'b'], container: container),
      );
      container.read(callPinnedTilesProvider.notifier).toggle('a');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('pin-a')));
      await tester.pump();
      expect(container.read(callPinnedTilesProvider), isEmpty);
      container.read(callPinnedTilesProvider.notifier).toggle('zzz');
      await tester.pump();
      await tester.pump();
      expect(container.read(callPinnedTilesProvider), isEmpty);
    });

    testWidgets('音量のあるウィンドウにだけ音量ボタンが出て、スライダーで値が変わる', (tester) async {
      double? changed;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            initialAppLocaleProvider.overrideWithValue(AppLocale.japanese),
          ],
          child: MaterialApp(
            home: SizedBox(
              width: 600,
              height: 400,
              child: CallTileStage(
                specs: [
                  CallTileSpec(
                    key: 'a',
                    volume: CallTileVolume(
                      value: 0.8,
                      onChanged: (v) => changed = v,
                    ),
                    build: (_) => const ColoredBox(color: Colors.grey),
                  ),
                  CallTileSpec(
                    key: 'b',
                    build: (_) => const ColoredBox(color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      expect(find.byKey(const ValueKey('volume-a')), findsOneWidget);
      expect(find.byKey(const ValueKey('volume-b')), findsNothing);
      expect(find.byKey(const ValueKey('volume-slider-a')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('volume-a')));
      await tester.pump();
      expect(find.byKey(const ValueKey('volume-slider-a')), findsOneWidget);
      final slider = find.byKey(const ValueKey('volume-slider-a'));
      // 縦のスライダー（回転した枠に入り、枠は幅より高さが大きい）。
      final box = find.ancestor(of: slider, matching: find.byType(RotatedBox));
      expect(box, findsOneWidget);
      final size = tester.getSize(
        find.ancestor(of: box, matching: find.byType(SizedBox)).first,
      );
      expect(size.height, greaterThan(size.width));
      await tester.tap(slider);
      await tester.pump();
      expect(changed, isNotNull);
      await tester.tap(find.byKey(const ValueKey('volume-a')));
      await tester.pump();
      expect(find.byKey(const ValueKey('volume-slider-a')), findsNothing);
    });

    testWidgets('スライダーの外（他のウィンドウ）を押すと閉じ、押した先の操作も効く', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            initialAppLocaleProvider.overrideWithValue(AppLocale.japanese),
          ],
          child: MaterialApp(
            home: SizedBox(
              width: 600,
              height: 400,
              child: CallTileStage(
                specs: [
                  CallTileSpec(
                    key: 'a',
                    volume: CallTileVolume(value: 0.5, onChanged: (_) {}),
                    build: (_) => const ColoredBox(color: Colors.grey),
                  ),
                  CallTileSpec(
                    key: 'b',
                    build: (_) => const ColoredBox(color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('volume-a')));
      await tester.pump();
      expect(find.byKey(const ValueKey('volume-slider-a')), findsOneWidget);
      // スライダー自身を押しても閉じない。
      await tester.tap(find.byKey(const ValueKey('volume-slider-a')));
      await tester.pump();
      expect(find.byKey(const ValueKey('volume-slider-a')), findsOneWidget);
      // 別のウィンドウのピンを押すと、スライダーが閉じ、ピン留めも効く。
      await tester.tap(find.byKey(const ValueKey('pin-b')));
      await tester.pump();
      expect(find.byKey(const ValueKey('volume-slider-a')), findsNothing);
      expect(find.byIcon(Icons.push_pin), findsOneWidget);
    });
  });

  group('CallMicStatus / CallMicBanner', () {
    Widget host(Widget child) => ProviderScope(
      overrides: [
        initialAppLocaleProvider.overrideWithValue(AppLocale.japanese),
      ],
      child: MaterialApp(home: Scaffold(body: child)),
    );

    testWidgets('マイクを使えない人にだけ「マイクを使えません」が出る', (tester) async {
      await tester.pumpWidget(
        host(const CallMicStatus(muted: false, unavailable: true)),
      );
      expect(find.text('マイクを使えません'), findsOneWidget);
      await tester.pumpWidget(
        host(const CallMicStatus(muted: true, unavailable: false)),
      );
      expect(find.text('マイクを使えません'), findsNothing);
      expect(find.byIcon(Icons.mic_off), findsOneWidget);
    });

    testWidgets('案内は、使えない間と入室時の注意の時だけ出る', (tester) async {
      await tester.pumpWidget(
        host(const CallMicBanner(unavailable: false, busyAtJoin: false)),
      );
      expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
      await tester.pumpWidget(
        host(const CallMicBanner(unavailable: true, busyAtJoin: false)),
      );
      expect(find.textContaining('声が相手に届いていません'), findsOneWidget);
      await tester.pumpWidget(
        host(const CallMicBanner(unavailable: false, busyAtJoin: true)),
      );
      expect(find.textContaining('可能性があります'), findsOneWidget);
    });
  });

  group('ScreenSharePreview', () {
    testWidgets('静止画が取れるまでは、共有中のカードとライブ切り替えのボタンが出る', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            initialAppLocaleProvider.overrideWithValue(AppLocale.japanese),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: ScreenSharePreview(
                trackOf: () => null,
                liveRenderer: RTCVideoRenderer(),
              ),
            ),
          ),
        ),
      );
      expect(find.text('画面を共有しています'), findsOneWidget);
      expect(find.byKey(const ValueKey('screen-preview-live')), findsOneWidget);
      expect(find.byIcon(Icons.videocam_off), findsOneWidget);
    });
  });

  group('isPortraitVideo', () {
    test('縦長だけtrue、大きさ未確定・横長・正方形はfalse', () {
      expect(isPortraitVideo(const RTCVideoValue()), isFalse);
      expect(
        isPortraitVideo(const RTCVideoValue(width: 480, height: 640)),
        isTrue,
      );
      expect(
        isPortraitVideo(const RTCVideoValue(width: 640, height: 480)),
        isFalse,
      );
      expect(
        isPortraitVideo(const RTCVideoValue(width: 500, height: 500)),
        isFalse,
      );
      // 横向きの映像が90度回転して届く時は縦長として扱う。
      expect(
        isPortraitVideo(
          const RTCVideoValue(width: 640, height: 480, rotation: 90),
        ),
        isTrue,
      );
    });
  });

  group('CallZoomable', () {
    Widget host({Object? resetKey}) => MaterialApp(
      home: Center(
        child: SizedBox(
          width: 200,
          height: 100,
          child: CallZoomable(
            resetKey: resetKey,
            child: const ColoredBox(
              key: ValueKey('zoom-child'),
              color: Colors.red,
            ),
          ),
        ),
      ),
    );

    double scaleOf(WidgetTester t) => t
        .widget<Transform>(
          find.descendant(
            of: find.byType(CallZoomable),
            matching: find.byType(Transform),
          ),
        )
        .transform
        .getMaxScaleOnAxis();

    testWidgets('ホイールで拡大でき、ダブルタップで等倍に戻る', (tester) async {
      await tester.pumpWidget(host());
      expect(scaleOf(tester), 1.0);

      final center = tester.getCenter(find.byType(CallZoomable));
      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      pointer.hover(center);
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, -300)));
      await tester.pump();
      expect(scaleOf(tester), greaterThan(1.5));

      await tester.tap(find.byType(CallZoomable));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.byType(CallZoomable));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(scaleOf(tester), 1.0);
    });

    testWidgets('倍率は上限（5倍）と下限（等倍）に収まる', (tester) async {
      await tester.pumpWidget(host());
      final center = tester.getCenter(find.byType(CallZoomable));
      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      pointer.hover(center);
      for (var i = 0; i < 10; i++) {
        await tester.sendEventToBinding(pointer.scroll(const Offset(0, -500)));
      }
      await tester.pump();
      expect(scaleOf(tester), 5.0);
      for (var i = 0; i < 20; i++) {
        await tester.sendEventToBinding(pointer.scroll(const Offset(0, 500)));
      }
      await tester.pump();
      expect(scaleOf(tester), 1.0);
    });

    testWidgets('resetKeyが変わると等倍に戻る', (tester) async {
      await tester.pumpWidget(host(resetKey: false));
      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      pointer.hover(tester.getCenter(find.byType(CallZoomable)));
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, -300)));
      await tester.pump();
      expect(scaleOf(tester), greaterThan(1.0));
      await tester.pumpWidget(host(resetKey: true));
      expect(scaleOf(tester), 1.0);
    });
  });
}
