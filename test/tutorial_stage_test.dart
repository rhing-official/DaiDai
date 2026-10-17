import 'package:daidai/features/guide/tutorial/tutorial_controller.dart';
import 'package:daidai/features/guide/tutorial/tutorial_overlay.dart';
import 'package:daidai/features/guide/tutorial/practice_home.dart';
import 'package:daidai/features/guide/tutorial/tutorial_stage_screen.dart';
import 'package:daidai/features/profile/enmusubi_page.dart';
import 'package:daidai/l10n/app_locale.dart';
import 'package:daidai/l10n/tutorial_content.dart';
import 'package:daidai/models/app_ui_style.dart';
import 'package:daidai/models/chat_layout_style.dart';
import 'package:daidai/models/conversation_sort_order.dart';
import 'package:daidai/models/message_time_format.dart';
import 'package:daidai/models/send_key_mode.dart';
import 'package:daidai/models/talks_list_layout_style.dart';
import 'package:daidai/providers/chat_layout_style_provider.dart';
import 'package:daidai/providers/conversation_sort_order_provider.dart';
import 'package:daidai/providers/draft_sync_enabled_provider.dart';
import 'package:daidai/providers/last_opened_room_provider.dart';
import 'package:daidai/providers/message_time_format_provider.dart';
import 'package:daidai/providers/send_key_mode_provider.dart';
import 'package:daidai/providers/talks_list_layout_style_provider.dart';
import 'package:daidai/providers/app_locale_provider.dart';
import 'package:daidai/providers/app_ui_style_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// 縁結びのガイド専用ルート（2026-10-17）。本物の縁結び画面を今の画面の上に開き、
// ガイドの状態と連動して閉じる（終了後は元の画面にそのまま戻る）こと。

late GoRouter _router;

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  String initialLocation = '/',
  double width = 800,
}) async {
  tester.view.physicalSize = Size(width, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  _router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: '/',
        builder: (context, _) => Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('HOME-WORK-IN-PROGRESS'),
                ElevatedButton(
                  key: const Key('start'),
                  onPressed: () {
                    ProviderScope.containerOf(context)
                        .read(tutorialControllerProvider.notifier)
                        .start(friendsTutorial);
                    context.push(friendsTutorial.stageRoute);
                  },
                  child: const Text('start'),
                ),
              ],
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/guide/practice',
        builder: (context, _) =>
            const TutorialStageScreen(child: PracticeHome()),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        initialAppLocaleProvider.overrideWithValue(AppLocale.japanese),
        initialAppUiStyleProvider.overrideWithValue(AppUiStyle.flat),
        initialSendKeyModeProvider.overrideWithValue(SendKeyMode.enterToSend),
        initialMessageTimeFormatProvider.overrideWithValue(
          MessageTimeFormat.h24,
        ),
        initialChatLayoutStyleProvider.overrideWithValue(
          ChatLayoutStyle.sideBySide,
        ),
        initialTalksListLayoutStyleProvider.overrideWithValue(
          TalksListLayoutStyle.standard,
        ),
        initialConversationSortOrderProvider.overrideWithValue(
          ConversationSortOrder.recent,
        ),
        initialLastOpenedRoomsProvider.overrideWithValue(const {}),
        initialDraftSyncEnabledProvider.overrideWithValue(false),
      ],
      child: MaterialApp.router(
        routerConfig: _router,
        builder: (context, child) => Stack(
          children: [
            Positioned.fill(child: child ?? const SizedBox.shrink()),
            const TutorialOverlay(),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _start(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('start')));
  // 遷移アニメーションが終わるまで進める（案内の層の毎フレームの更新で
  // pumpAndSettleは終わらない）。
  await _settle(tester);
  await _settle(tester);
}

void main() {
  testWidgets('開始すると練習用のホームが開き、最初に「身だしなみ」の手順が案内される', (tester) async {
    final container = await _pump(tester);
    await _start(tester);
    expect(find.byType(PracticeHome), findsOneWidget);
    expect(container.read(tutorialControllerProvider)?.index, 0);
    expect(find.text('まず「身だしなみ」を押します'), findsOneWidget);
    expect(find.text('1 / 5'), findsOneWidget);
  });

  testWidgets('道順を押す→コピーを押す→QRの説明→読み取りボタンの説明→完了→閉じる、で元の画面に戻る', (tester) async {
    final container = await _pump(tester);
    await _start(tester);

    // 1手順目: ナビチップの「身だしなみ」、2手順目: 「縁結び」を押す。
    await tester.tap(find.byIcon(Icons.face_outlined));
    await tester.pump(const Duration(milliseconds: 200));
    await _settle(tester);
    expect(find.textContaining('「縁結び」を押します'), findsOneWidget);
    await tester.tap(find.text('縁結び').last);
    await tester.pump(const Duration(milliseconds: 200));
    await _settle(tester);
    expect(find.byType(EnmusubiPage), findsOneWidget);

    // 3手順目: コピーボタンを押す。
    await tester.tap(find.byIcon(Icons.copy_outlined));
    await tester.pump(const Duration(milliseconds: 200));
    await _settle(tester);
    expect(find.textContaining('QRコードです'), findsOneWidget);

    // 2・3手順目は押さない手順（「次へ」で進む）。読み取りボタンを押しても何も起きない。
    await tester.tap(find.byKey(const ValueKey('tutorial-next')));
    await _settle(tester);
    expect(find.textContaining('読み取るときは'), findsOneWidget);
    await tester.tap(find.text('QRコードを読み取る'), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 300));
    expect(container.read(tutorialControllerProvider)?.index, 4);
    await tester.tap(find.byKey(const ValueKey('tutorial-next')));
    await _settle(tester);

    // 完了カード。
    expect(container.read(tutorialControllerProvider)?.done, isTrue);
    expect(find.text('できました！'), findsOneWidget);
    expect(find.textContaining('招待リンクを友達に'), findsOneWidget);

    // 閉じると、ステージ画面も閉じて元の画面（作業中の状態）に戻る。
    await tester.tap(find.text('閉じる'));
    await _settle(tester);
    await _settle(tester);
    expect(container.read(tutorialControllerProvider), isNull);
    expect(find.byType(PracticeHome), findsNothing);
    expect(find.text('HOME-WORK-IN-PROGRESS'), findsOneWidget);
  });

  testWidgets('狭い画面（モバイル）でも、身だしなみ→縁結びの道順を押して進める', (tester) async {
    final container = await _pump(tester, width: 400);
    await _start(tester);
    await tester.tap(find.byIcon(Icons.face_outlined));
    await tester.pump(const Duration(milliseconds: 200));
    await _settle(tester);
    await tester.tap(find.text('縁結び').last);
    await tester.pump(const Duration(milliseconds: 200));
    await _settle(tester);
    await _settle(tester);
    expect(find.byType(EnmusubiPage), findsOneWidget);
    expect(container.read(tutorialControllerProvider)?.index, 2);
  });

  testWidgets('「やめる」でガイドもステージ画面も閉じ、元の画面に戻る', (tester) async {
    final container = await _pump(tester);
    await _start(tester);
    await tester.tap(find.text('やめる'));
    await _settle(tester);
    await _settle(tester);
    expect(container.read(tutorialControllerProvider), isNull);
    expect(find.byType(PracticeHome), findsNothing);
    expect(find.text('HOME-WORK-IN-PROGRESS'), findsOneWidget);
  });

  testWidgets('ユーザーがステージ画面を戻る操作で閉じると、ガイドも中断される', (tester) async {
    final container = await _pump(tester);
    await _start(tester);
    _router.pop();
    await _settle(tester);
    await _settle(tester);
    expect(container.read(tutorialControllerProvider), isNull);
    expect(find.text('HOME-WORK-IN-PROGRESS'), findsOneWidget);
  });

  testWidgets('ガイドが実行されていないのにステージ画面のURLが開かれたら、ホームへ戻る', (tester) async {
    await _pump(tester, initialLocation: '/guide/practice');
    await _settle(tester);
    await _settle(tester);
    expect(find.byType(PracticeHome), findsNothing);
    expect(find.text('HOME-WORK-IN-PROGRESS'), findsOneWidget);
  });
}
