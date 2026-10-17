import 'dart:ui' as ui;

import 'package:daidai/features/guide/guide_pages.dart';
import 'package:daidai/features/guide/tutorial/hand_drawn_circle.dart';
import 'package:daidai/features/guide/tutorial/tutorial_controller.dart';
import 'package:daidai/features/guide/tutorial/tutorial_overlay.dart';
import 'package:daidai/features/guide/tutorial/tutorial_target.dart';
import 'package:daidai/l10n/app_locale.dart';
import 'package:daidai/l10n/guide_content.dart';
import 'package:daidai/l10n/tutorial_content.dart';
import 'package:daidai/providers/app_locale_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// 操作を促すインタラクティブなガイド（2026-10-17）。穴の外のタップは吸収され、
// 穴の中（目印）のタップだけがボタンへ届いて手順が進むこと、いつでもやめられることを確認する。

const _script = TutorialScript(
  id: 'test',
  steps: [
    TutorialStep(targetId: 'a', caption: GuideText('Aを押す', 'Tap A')),
    TutorialStep(targetId: 'b', caption: GuideText('Bを押す', 'Tap B')),
  ],
  doneMessage: GuideText('完了しました', 'Finished'),
  stageRoute: '/stage',
);

class _Counts {
  int a = 0;
  int b = 0;
  int other = 0;
}

Future<ProviderContainer> _pump(WidgetTester tester, _Counts counts) async {
  tester.view.physicalSize = const Size(800, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        initialAppLocaleProvider.overrideWithValue(AppLocale.japanese),
      ],
      child: MaterialApp(
        builder: (context, child) => Stack(
          children: [
            Positioned.fill(child: child ?? const SizedBox.shrink()),
            const TutorialOverlay(),
          ],
        ),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TutorialTarget(
                  id: 'a',
                  child: ElevatedButton(
                    key: const Key('A'),
                    onPressed: () => counts.a++,
                    child: const Text('A'),
                  ),
                ),
                const SizedBox(height: 200),
                TutorialTarget(
                  id: 'b',
                  child: ElevatedButton(
                    key: const Key('B'),
                    onPressed: () => counts.b++,
                    child: const Text('B'),
                  ),
                ),
                const SizedBox(height: 200),
                ElevatedButton(
                  key: const Key('other'),
                  onPressed: () => counts.other++,
                  child: const Text('other'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return ProviderScope.containerOf(tester.element(find.byKey(const Key('A'))));
}

/// 案内の層が目印の位置を取り込み、丸を描き始めるまで数フレーム進める。
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('ガイドを実行していない間は、何も吸収せずボタンが普通に押せる', (tester) async {
    final counts = _Counts();
    await _pump(tester, counts);
    await tester.tap(find.byKey(const Key('other')));
    await tester.tap(find.byKey(const Key('A')));
    expect(counts.other, 1);
    expect(counts.a, 1);
    expect(find.text('やめる'), findsNothing);
  });

  testWidgets('実行中は穴の外のタップを吸収し、穴（目印）のタップだけが届いて次へ進む', (tester) async {
    final counts = _Counts();
    final container = await _pump(tester, counts);
    container.read(tutorialControllerProvider.notifier).start(_script);
    await _settle(tester);
    expect(find.text('Aを押す'), findsOneWidget);
    expect(find.text('1 / 2'), findsOneWidget);

    // 穴の外（今の手順ではないB・その他）は押せない。
    await tester.tap(find.byKey(const Key('B')), warnIfMissed: false);
    await tester.tap(find.byKey(const Key('other')), warnIfMissed: false);
    expect(counts.b, 0);
    expect(counts.other, 0);

    // 穴の中のAを押すと、Aの処理が実行されて2手順目へ。
    await tester.tap(find.byKey(const Key('A')));
    expect(counts.a, 1);
    await tester.pump(const Duration(milliseconds: 200));
    await _settle(tester);
    expect(find.text('Bを押す'), findsOneWidget);
    expect(find.text('2 / 2'), findsOneWidget);

    // 2手順目では、Aはもう押せない。
    await tester.tap(find.byKey(const Key('A')), warnIfMissed: false);
    expect(counts.a, 1);
  });

  testWidgets('最後の手順を押すと完了カードが出て、閉じるとガイドが終わる', (tester) async {
    final counts = _Counts();
    final container = await _pump(tester, counts);
    final controller = container.read(tutorialControllerProvider.notifier);
    controller.start(_script);
    await _settle(tester);
    await tester.tap(find.byKey(const Key('A')));
    await tester.pump(const Duration(milliseconds: 200));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('B')));
    expect(counts.b, 1);
    await tester.pump(const Duration(milliseconds: 200));
    await _settle(tester);

    expect(container.read(tutorialControllerProvider)?.done, isTrue);
    expect(find.text('できました！'), findsOneWidget);
    expect(find.text('完了しました'), findsOneWidget);
    // 完了カードが出ている間も、背後の操作は吸収される。
    await tester.tap(find.byKey(const Key('other')), warnIfMissed: false);
    expect(counts.other, 0);

    await tester.tap(find.text('閉じる'));
    await tester.pump();
    expect(container.read(tutorialControllerProvider), isNull);
    await tester.tap(find.byKey(const Key('other')));
    expect(counts.other, 1);
  });

  testWidgets('「やめる」で中断でき、その後は普通に操作できる', (tester) async {
    final counts = _Counts();
    final container = await _pump(tester, counts);
    container.read(tutorialControllerProvider.notifier).start(_script);
    await _settle(tester);
    await tester.tap(find.text('やめる'));
    await tester.pump();
    expect(container.read(tutorialControllerProvider), isNull);
    await tester.tap(find.byKey(const Key('other')));
    expect(counts.other, 1);
  });

  testWidgets('Escキーでも中断できる', (tester) async {
    final counts = _Counts();
    final container = await _pump(tester, counts);
    container.read(tutorialControllerProvider.notifier).start(_script);
    await _settle(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(container.read(tutorialControllerProvider), isNull);
  });

  testWidgets('目印が見つからない間は画面全体を吸収して待機し、やめるだけは押せる', (tester) async {
    final counts = _Counts();
    final container = await _pump(tester, counts);
    container
        .read(tutorialControllerProvider.notifier)
        .start(
          const TutorialScript(
            id: 'missing',
            steps: [
              TutorialStep(
                targetId: 'does-not-exist',
                caption: GuideText('見えないボタン', 'Hidden button'),
              ),
            ],
            doneMessage: GuideText('完了', 'Done'),
            stageRoute: '/stage',
          ),
        );
    await _settle(tester);
    await tester.tap(find.byKey(const Key('A')), warnIfMissed: false);
    await tester.tap(find.byKey(const Key('other')), warnIfMissed: false);
    expect(counts.a, 0);
    expect(counts.other, 0);
    // 目印が見つかるまでは、吹き出しを仮の位置に出さない。
    expect(find.text('見えないボタン'), findsNothing);
    // 3秒待つと、進まない時の案内つきで吹き出しが出る。
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('見えないボタン'), findsOneWidget);
    expect(find.textContaining('「やめる」'), findsOneWidget);
    await tester.tap(find.text('やめる'));
    await tester.pump();
    expect(container.read(tutorialControllerProvider), isNull);
  });

  testWidgets('押さない手順（情報の手順）は穴の上も吸収し、「次へ」で進む', (tester) async {
    final counts = _Counts();
    final container = await _pump(tester, counts);
    container
        .read(tutorialControllerProvider.notifier)
        .start(
          const TutorialScript(
            id: 'info',
            stageRoute: '/stage',
            steps: [
              TutorialStep(
                targetId: 'a',
                requiresTap: false,
                caption: GuideText('Aの説明', 'About A'),
              ),
              TutorialStep(targetId: 'b', caption: GuideText('Bを押す', 'Tap B')),
            ],
            doneMessage: GuideText('完了', 'Done'),
          ),
        );
    await _settle(tester);
    expect(find.text('Aの説明'), findsOneWidget);
    // 目印のAを押しても、押さない手順なので何も起きず進まない。
    await tester.tap(find.byKey(const Key('A')), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 300));
    expect(counts.a, 0);
    expect(find.text('Aの説明'), findsOneWidget);
    // 「次へ」で次の手順（押させる手順）へ。
    await tester.tap(find.byKey(const ValueKey('tutorial-next')));
    await _settle(tester);
    expect(find.text('Bを押す'), findsOneWidget);
    expect(find.byKey(const ValueKey('tutorial-next')), findsNothing);
  });

  group('手描きの丸', () {
    const rect = Rect.fromLTWH(100, 100, 80, 40);

    test('同じ引数なら必ず同じ形になる', () {
      final a = handDrawnCirclePath(rect, seed: 5).getBounds();
      final b = handDrawnCirclePath(rect, seed: 5).getBounds();
      expect(a, b);
      expect(handDrawnCirclePath(rect, seed: 6).getBounds(), isNot(a));
    });

    test('対象を囲み、進捗に応じて描かれる長さが増える', () {
      final path = handDrawnCirclePath(rect);
      expect(path.getBounds().contains(rect.center), isTrue);
      expect(path.getBounds().width, greaterThan(rect.width));
      double lengthOf(Path p) =>
          p.computeMetrics().fold(0.0, (sum, m) => sum + m.length);
      final quarter = lengthOf(partialPath(path, 0.25));
      final half = lengthOf(partialPath(path, 0.5));
      final full = lengthOf(partialPath(path, 1));
      expect(quarter, lessThan(half));
      expect(half, lessThan(full));
      expect(lengthOf(partialPath(path, 0)), 0);
    });
  });

  testWidgets('ベールは穴の中だけ透明に抜け、外は暗くなる', (tester) async {
    const size = Size(200, 100);
    const hole = Rect.fromLTWH(60, 30, 80, 40);
    final recorder = ui.PictureRecorder();
    const TutorialScrimPainter(hole: hole).paint(Canvas(recorder), size);
    final picture = recorder.endRecording();
    final image = await tester.runAsync(
      () => picture.toImage(size.width.toInt(), size.height.toInt()),
    );
    final bytes = await tester.runAsync(
      () => image!.toByteData(format: ui.ImageByteFormat.rawRgba),
    );
    int alphaAt(int x, int y) =>
        bytes!.getUint8((y * size.width.toInt() + x) * 4 + 3);
    // 穴の中央は完全に透明（下のボタンが暗くならない）、穴の外は暗い塗り。
    expect(alphaAt(100, 50), 0);
    expect(alphaAt(10, 10), greaterThan(100));
    expect(alphaAt(190, 90), greaterThan(100));
    // 穴が無ければ全面が暗い。
    final recorder2 = ui.PictureRecorder();
    const TutorialScrimPainter(hole: null).paint(Canvas(recorder2), size);
    final image2 = await tester.runAsync(
      () => recorder2.endRecording().toImage(200, 100),
    );
    final bytes2 = await tester.runAsync(
      () => image2!.toByteData(format: ui.ImageByteFormat.rawRgba),
    );
    expect(bytes2!.getUint8((50 * 200 + 100) * 4 + 3), greaterThan(100));
  });

  group('丸の画面内への収め方', () {
    test('はみ出していなければそのまま', () {
      final fit = fitAxes(
        const Rect.fromLTRB(20, 20, 80, 80),
        const Rect.fromLTWH(0, 0, 200, 200),
        margin: 6,
      );
      expect(fit.dx, (scale: 1.0, offset: 0.0));
      expect(fit.dy, (scale: 1.0, offset: 0.0));
    });

    test('左にはみ出す時は、左端だけを内側へ寄せる（右端は動かさない）', () {
      const content = Rect.fromLTRB(-20, 50, 60, 130);
      final fit = fitAxes(
        content,
        const Rect.fromLTWH(0, 0, 200, 200),
        margin: 6,
      );
      expect(content.left * fit.dx.scale + fit.dx.offset, closeTo(6, 1e-9));
      expect(content.right * fit.dx.scale + fit.dx.offset, closeTo(60, 1e-9));
      expect(fit.dy, (scale: 1.0, offset: 0.0));
    });

    test('右・下にはみ出す時は、はみ出す端を内側へ寄せる', () {
      const content = Rect.fromLTRB(150, 150, 230, 230);
      final fit = fitAxes(
        content,
        const Rect.fromLTWH(0, 0, 200, 200),
        margin: 6,
      );
      expect(content.right * fit.dx.scale + fit.dx.offset, closeTo(194, 1e-9));
      expect(content.left * fit.dx.scale + fit.dx.offset, closeTo(150, 1e-9));
      expect(content.bottom * fit.dy.scale + fit.dy.offset, closeTo(194, 1e-9));
    });
  });

  group('台本', () {
    test('縁結びの台本の目印idは、定義済みの目印だけを指す', () {
      const known = {
        TutorialTargetIds.navProfile,
        TutorialTargetIds.profileEnmusubi,
        TutorialTargetIds.enmusubiCopy,
        TutorialTargetIds.enmusubiQr,
        TutorialTargetIds.enmusubiScan,
      };
      for (final step in friendsTutorial.steps) {
        expect(known, contains(step.targetId));
        expect(step.caption.ja.trim(), isNotEmpty);
        expect(step.caption.en.trim(), isNotEmpty);
      }
      expect(friendsTutorial.steps, hasLength(5));
      // 道順（身だしなみ→縁結び）とコピーは押させ、QR・読み取りボタンは丸で示して
      // 説明するだけ（カメラの許可が絡む）。
      expect(friendsTutorial.steps.map((s) => s.requiresTap), [
        true,
        true,
        true,
        false,
        false,
      ]);
      expect(friendsTutorial.stageRoute, '/guide/enmusubi');
      expect(tutorialScriptOf('friends'), friendsTutorial);
      expect(tutorialScriptOf('no-such'), isNull);
    });

    test('台本のidは機能別ガイドのidに対応する', () {
      final topicIds = guideTopics.map((t) => t.id).toSet();
      for (final script in tutorialScripts) {
        expect(topicIds, contains(script.id));
      }
    });
  });

  testWidgets('一覧で縁結びを押すと、説明ページを挟まずその場でガイドが始まり専用ルートが開く', (tester) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) =>
              Scaffold(body: GuideTopicListPage(onReplayFirst: () {})),
        ),
        GoRoute(
          path: '/guide/enmusubi',
          builder: (_, _) => const Scaffold(body: Text('STAGE')),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          initialAppLocaleProvider.overrideWithValue(AppLocale.japanese),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(GuideTopicListPage)),
    );
    expect(container.read(tutorialControllerProvider), isNull);
    await tester.tap(find.byKey(const ValueKey('guide-topic-friends')));
    await tester.pumpAndSettle();
    expect(container.read(tutorialControllerProvider)?.script, friendsTutorial);
    expect(find.text('STAGE'), findsOneWidget);
  });

  testWidgets('台本が無い機能を押すと「準備中」と出るだけで、ガイドは始まらない', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          initialAppLocaleProvider.overrideWithValue(AppLocale.japanese),
        ],
        child: MaterialApp(
          home: Scaffold(body: GuideTopicListPage(onReplayFirst: () {})),
        ),
      ),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(GuideTopicListPage)),
    );
    await tester.ensureVisible(find.byKey(const ValueKey('guide-topic-notes')));
    await tester.tap(find.byKey(const ValueKey('guide-topic-notes')));
    await tester.pump();
    expect(find.text('このガイドは準備中です'), findsOneWidget);
    expect(container.read(tutorialControllerProvider), isNull);
  });
}
