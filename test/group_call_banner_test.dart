import 'package:daidai/features/call/group_incoming_call_listener.dart';
import 'package:daidai/l10n/app_locale.dart';
import 'package:daidai/models/app_ui_style.dart';
import 'package:daidai/providers/app_locale_provider.dart';
import 'package:daidai/models/group_call.dart';
import 'package:daidai/providers/accent_color_provider.dart';
import 'package:daidai/providers/app_ui_style_provider.dart';
import 'package:daidai/theme/gekiga/gekiga_colors.dart';
import 'package:daidai/widgets/glass/glass_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

GroupCall _call(String id) => GroupCall(
  groupCallId: id,
  groupId: 'g1',
  initiatorId: 'u2',
  memberIds: const ['u1', 'u2'],
  status: GroupCallStatus.active,
);

ProviderContainer _container([AppUiStyle style = AppUiStyle.flat]) =>
    ProviderContainer(
      overrides: [
        initialAppUiStyleProvider.overrideWithValue(style),
        initialAccentColorProvider.overrideWithValue(Colors.orange),
        initialAppLocaleProvider.overrideWithValue(AppLocale.japanese),
      ],
    );

Future<ProviderContainer> _pump(WidgetTester tester) async {
  final container = _container();
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Positioned.fill(child: SizedBox()),
              GroupCallBannerOverlay(),
            ],
          ),
        ),
      ),
    ),
  );
  return container;
}

void main() {
  testWidgets('バナーは改行して表示され、上スワイプで消えて着信音停止の通知が飛ぶ', (tester) async {
    final container = await _pump(tester);
    var stopped = 0;
    final notifier = container.read(groupCallBannersProvider.notifier);
    notifier.onDismissed = () => stopped++;
    notifier.add(PendingGroupCallBanner(call: _call('c1'), groupName: '広場A'));
    await tester.pump();

    expect(find.text('広場Aで通話が始まりました。\nタップして参加'), findsOneWidget);

    await tester.drag(find.byType(Dismissible), const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(container.read(groupCallBannersProvider), isEmpty);
    expect(stopped, 1);
  });

  testWidgets('タップで参加処理が呼ばれ、×でも閉じて着信音停止の通知が飛ぶ', (tester) async {
    final container = await _pump(tester);
    var joined = 0;
    var stopped = 0;
    final notifier = container.read(groupCallBannersProvider.notifier);
    notifier.onJoin = (_) => joined++;
    notifier.onDismissed = () => stopped++;
    notifier.add(PendingGroupCallBanner(call: _call('c1'), groupName: '広場A'));
    await tester.pump();

    await tester.tap(find.textContaining('タップして参加'));
    expect(joined, 1);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    expect(container.read(groupCallBannersProvider), isEmpty);
    expect(stopped, 1);
  });

  test('retainOnlyは終わった通話のバナーだけ消す', () {
    final container = _container();
    addTearDown(container.dispose);
    final n = container.read(groupCallBannersProvider.notifier);
    n.add(PendingGroupCallBanner(call: _call('c1'), groupName: 'A'));
    n.add(PendingGroupCallBanner(call: _call('c2'), groupName: 'B'));
    n.retainOnly({'c2'});
    expect(
      container.read(groupCallBannersProvider).map((b) => b.call.groupCallId),
      ['c2'],
    );
  });

  group('UIスタイル別の見た目', () {
    Future<void> pumpStyled(WidgetTester tester, AppUiStyle style) async {
      final container = _container(style);
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: ThemeData(
              colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
            ),
            home: const Scaffold(
              body: Stack(children: [GroupCallBannerOverlay()]),
            ),
          ),
        ),
      );
      container
          .read(groupCallBannersProvider.notifier)
          .add(PendingGroupCallBanner(call: _call('c1'), groupName: '広場A'));
      await tester.pump();
    }

    Material bannerMaterial(WidgetTester tester) => tester
        .widgetList<Material>(
          find.descendant(
            of: find.byType(Dismissible),
            matching: find.byType(Material),
          ),
        )
        .first;

    testWidgets('劇画はモノクロ（青緑のprimaryContainerを使わない）', (tester) async {
      await pumpStyled(tester, AppUiStyle.gekiga);
      expect(bannerMaterial(tester).color, GekigaColors.panel);
    });

    testWidgets('フラットはアクセントカラー（primary）で影なし', (tester) async {
      await pumpStyled(tester, AppUiStyle.flat);
      final m = bannerMaterial(tester);
      expect(
        m.color,
        Theme.of(tester.element(find.byType(Dismissible))).colorScheme.primary,
      );
      expect(m.elevation, 0);
    });

    testWidgets('ガラスはGlassSurface（ぼかし・縁の光彩）で包まれる', (tester) async {
      await pumpStyled(tester, AppUiStyle.glass);
      expect(
        find.descendant(
          of: find.byType(Dismissible),
          matching: find.byType(GlassSurface),
        ),
        findsOneWidget,
      );
    });
  });
}
