import 'package:daidai/features/chat/proposal_banner.dart';
import 'package:daidai/models/app_ui_style.dart';
import 'package:daidai/providers/accent_color_provider.dart';
import 'package:daidai/providers/app_ui_style_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FixedStyle extends AppUiStyleNotifier {
  _FixedStyle(this._style);
  final AppUiStyle _style;

  @override
  AppUiStyle build() => _style;
}

void main() {
  Future<void> pump(
    WidgetTester tester,
    double width, {
    ThemeData? theme,
    AppUiStyle uiStyle = AppUiStyle.flat,
  }) async {
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          initialAccentColorProvider.overrideWithValue(const Color(0xFFF08300)),
          appUiStyleProvider.overrideWith(() => _FixedStyle(uiStyle)),
        ],
        child: MaterialApp(
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

  for (final style in AppUiStyle.values) {
    testWidgets('${style.name}でも文と2つのボタンが出る', (tester) async {
      await pump(tester, 400, uiStyle: style);
      expect(find.byKey(const Key('msg')), findsOneWidget);
      expect(find.byKey(const Key('decline')), findsOneWidget);
      expect(find.byKey(const Key('accept')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('文字は面と反対の色（劇画は白、フラットは中立のonSurface）', (tester) async {
    await pump(tester, 400, uiStyle: AppUiStyle.gekiga);
    final gekiga = tester.widget<DefaultTextStyle>(
      find
          .ancestor(
            of: find.byKey(const Key('msg')),
            matching: find.byType(DefaultTextStyle),
          )
          .first,
    );
    expect(gekiga.style.color, Colors.white);
  });
}
