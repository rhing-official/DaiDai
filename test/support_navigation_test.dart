import 'package:daidai/features/support/support_tab.dart';
import 'package:daidai/l10n/app_locale.dart';
import 'package:daidai/providers/app_locale_provider.dart';
import 'package:daidai/widgets/swipe_gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// 運営タブの狭い画面（サイドバー+ドリルダウン方式）でのカテゴリ切り替え
// スワイプの回帰テスト。760のブレークポイント未満の幅にする。
Future<void> _pumpSupportTabNarrow(WidgetTester tester) async {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        initialAppLocaleProvider.overrideWithValue(AppLocale.japanese),
      ],
      child: const MaterialApp(home: Scaffold(body: SupportTab())),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('狭い画面のドリルダウン中に左スワイプで次のカテゴリへ切り替え、右スワイプで一覧へ戻る（回帰テスト）', (
    tester,
  ) async {
    await _pumpSupportTabNarrow(tester);

    // カテゴリ一覧から「お知らせ」（ホームページのURL→お知らせ→質問フォームの
    // 2番目）へドリルダウンする。
    await tester.tap(find.text('お知らせ'));
    await tester.pumpAndSettle();
    expect(find.text('お知らせ'), findsWidgets);

    // 左スワイプで次のカテゴリ（質問フォーム）へ。
    await tester.fling(find.byType(SwipeBackDetector), const Offset(-300, 0), 1000);
    await tester.pumpAndSettle();
    expect(find.text('お知らせ'), findsNothing);
    expect(find.text('質問フォーム'), findsWidgets);

    // 右スワイプすると、隣接カテゴリではなく常にカテゴリ一覧へ戻る。
    await tester.fling(find.byType(SwipeBackDetector), const Offset(300, 0), 1000);
    await tester.pumpAndSettle();
    expect(find.byType(SwipeBackDetector), findsNothing);
    expect(find.text('お知らせ'), findsOneWidget); // 一覧のカテゴリ名として表示される
  });
}
