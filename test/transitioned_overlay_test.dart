import 'package:daidai/widgets/transitioned_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('動きながら現れ、閉じる動きを終えてから取り除かれる', (tester) async {
    late VoidCallback close;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () {
              close = showTransitionedOverlay(
                Overlay.of(context),
                builder: (context, close) =>
                    GestureDetector(onTap: close, child: const Text('panel')),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    expect(find.text('panel'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));

    close();
    await tester.pump(const Duration(milliseconds: 50));
    // 閉じる動きの途中は、まだ残っている。
    expect(find.text('panel'), findsOneWidget);
    close(); // 再生中の呼び出しは無視される。
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('panel'), findsNothing);
  });
}
