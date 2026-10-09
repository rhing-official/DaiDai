import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// `chat_screen.dart`のヘッダーのボタン列（`Flexible`＋`FittedBox`＋`Row`）が、
/// 幅が足りなくてもあふれずに全ボタンを収める構造であることの検証
/// （右端のハンバーガーメニューが見えない不具合の回帰テスト、2026-10-07）。
Widget _app() {
  return MaterialApp(
    home: Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        actions: [
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < 8; i++)
                    IconButton(
                      key: ValueKey('b$i'),
                      icon: const Icon(Icons.circle),
                      onPressed: () {},
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

Future<void> _pump(WidgetTester tester, double width) async {
  tester.view.physicalSize = Size(width, 600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(_app());
}

void main() {
  for (final width in const [320.0, 345.0, 360.0]) {
    testWidgets('幅${width.toInt()}でもあふれず、最後のボタンが画面内に収まる', (tester) async {
      await _pump(tester, width);
      expect(tester.takeException(), isNull);
      final last = tester.getRect(find.byKey(const ValueKey('b7')));
      expect(last.right, lessThanOrEqualTo(width + 0.5));
      expect(last.left, greaterThanOrEqualTo(0));
    });
  }

  testWidgets('幅が十分ある時は縮小されない（各ボタン48dp）', (tester) async {
    await _pump(tester, 800);
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byKey(const ValueKey('b0'))).width, 48);
  });
}
