import 'package:daidai/features/chat/proposal_banner.dart';
import 'package:daidai/models/app_ui_style.dart';
import 'package:daidai/providers/app_ui_style_provider.dart';
import 'package:daidai/theme/chalk/chalk_paint.dart';
import 'package:daidai/theme/chalk/chalk_theme.dart';
import 'package:daidai/utils/auto_dismiss_banner.dart';
import 'package:daidai/widgets/chalk_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Chalk extends AppUiStyleNotifier {
  @override
  AppUiStyle build() => AppUiStyle.chalk;
}

void main() {
  final theme = ChalkTheme.build(const Color(0xFFF08300), null);

  testWidgets('ChalkBannerFrame: 塗らず、チョークの線（onSurface）で囲む', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: const Scaffold(body: ChalkBannerFrame(child: Text('バナー'))),
      ),
    );
    final box = tester.widget<DecoratedBox>(
      find.descendant(
        of: find.byType(ChalkBannerFrame),
        matching: find.byType(DecoratedBox),
      ),
    );
    final d = box.decoration as ChalkBoxDecoration;
    expect(d.color, isNull);
    expect(d.lineColor, theme.colorScheme.onSurface);
  });

  testWidgets('提案バナー: チョークは、版画の太い黒枠でなく、チョークの枠', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appUiStyleProvider.overrideWith(_Chalk.new)],
        child: MaterialApp(
          theme: theme,
          home: Scaffold(
            body: ProposalBannerLayout(
              message: const Text('相手が絶縁を提案しています'),
              actions: [TextButton(onPressed: () {}, child: const Text('OK'))],
            ),
          ),
        ),
      ),
    );
    expect(find.byType(ChalkBannerFrame), findsOneWidget);
  });

  testWidgets('一時バナー: チョークは、地の色で塗ったチョークの枠。影は無い', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: Builder(
            builder: (c) {
              ctx = c;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    final timer = showAutoDismissBanner(ctx, message: '保存しました。');
    await tester.pump();
    final frame = tester.widget<ChalkBannerFrame>(
      find.byType(ChalkBannerFrame),
    );
    expect(frame.color, theme.colorScheme.surface);
    expect(find.text('保存しました'), findsOneWidget);
    expect(
      tester
          .widgetList<Material>(find.byType(Material))
          .any((m) => m.elevation > 0),
      isFalse,
    );
    timer.cancel();
    dismissAutoDismissBanner();
    await tester.pump();
  });

  testWidgets('plainBannerSurface: チョークなら枠、それ以外は従来の面', (tester) async {
    Future<void> pumpWith(ThemeData t) => tester.pumpWidget(
      MaterialApp(
        theme: t,
        home: Scaffold(
          body: Builder(
            builder: (c) => plainBannerSurface(c, child: const Text('x')),
          ),
        ),
      ),
    );
    await pumpWith(theme);
    expect(find.byType(ChalkBannerFrame), findsOneWidget);
    await pumpWith(ThemeData());
    await tester.pumpAndSettle(); // テーマの切り替えのアニメーションを終える
    expect(find.byType(ChalkBannerFrame), findsNothing);
  });
}
