import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daidai/widgets/transitioned_overlay.dart';

void main() {
  Future<TransitionedOverlayHandle> open(WidgetTester tester) async {
    late TransitionedOverlayHandle handle;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () {
              handle = showTransitionedOverlayHandle(
                Overlay.of(context),
                builder: (_, _) => const Center(child: Text('popup')),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    return handle;
  }

  testWidgets('close()は閉じる動きを再生してから取り除く', (tester) async {
    final handle = await open(tester);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('popup'), findsOneWidget);

    handle.close();
    await tester.pump(const Duration(milliseconds: 60));
    // 動きの途中は、まだ残っている。
    expect(find.text('popup'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('popup'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('removeNow()は動きなしで直ちに取り除く', (tester) async {
    final handle = await open(tester);
    await tester.pump(const Duration(milliseconds: 400));
    handle.removeNow();
    await tester.pump();
    expect(find.text('popup'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('close()の再生中にremoveNow()しても、エラーにならない', (tester) async {
    final handle = await open(tester);
    await tester.pump(const Duration(milliseconds: 400));
    handle.close();
    await tester.pump(const Duration(milliseconds: 60));
    handle.removeNow();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('popup'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
