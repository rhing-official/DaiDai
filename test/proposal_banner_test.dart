import 'package:daidai/features/chat/proposal_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(
    WidgetTester tester,
    double width, {
    ThemeData? theme,
  }) async {
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: ProposalBannerLayout(
            message: const Text('相手が絶縁を提案しています', key: Key('msg')),
            actions: [
              TextButton(
                key: const Key('decline'),
                onPressed: () {},
                child: const Text('今は同意しない'),
              ),
              FilledButton(
                key: const Key('accept'),
                style: proposalAcceptButtonStyle(),
                onPressed: () {},
                child: const Text('同意する'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  testWidgets('狭い幅では文の下にボタンが2段で並ぶ', (tester) async {
    await pump(tester, 360);
    final msg = tester.getRect(find.byKey(const Key('msg')));
    final accept = tester.getRect(find.byKey(const Key('accept')));
    expect(accept.top, greaterThanOrEqualTo(msg.bottom));
    // 右寄せ
    expect(accept.right, greaterThan(300));
  });

  testWidgets('広い幅では1行に並ぶ', (tester) async {
    await pump(tester, 900);
    final msg = tester.getRect(find.byKey(const Key('msg')));
    final accept = tester.getRect(find.byKey(const Key('accept')));
    expect(accept.left, greaterThan(msg.right));
    expect((accept.center.dy - msg.center.dy).abs(), lessThan(20));
  });

  for (final brightness in Brightness.values) {
    testWidgets('「同意する」は${brightness.name}でも同じ濃い赤＋白文字', (tester) async {
      await pump(
        tester,
        400,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.orange,
            brightness: brightness,
          ),
        ),
      );
      final button = tester.widget<FilledButton>(
        find.byKey(const Key('accept')),
      );
      final style = button.style!;
      expect(style.backgroundColor!.resolve({}), Colors.red.shade700);
      expect(style.foregroundColor!.resolve({}), Colors.white);
    });
  }
}
