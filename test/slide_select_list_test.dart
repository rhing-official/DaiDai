import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:daidai/providers/category_list_alignment_provider.dart';
import 'package:daidai/providers/home_shell_providers.dart';
import 'package:daidai/widgets/slide_select_list.dart';

Future<List<int>> _pump(WidgetTester tester) async {
  final ended = <int>[];
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: SlideSelectList(
            itemCount: 5,
            onSlideEnd: ended.add,
            builder: (context, keyFor, slidingIndex) => Column(
              children: [
                for (var i = 0; i < 5; i++)
                  SizedBox(key: keyFor(i), height: 60, child: Text('item $i')),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  return ended;
}

void main() {
  _bottomAlignTests();
  testWidgets('縦になぞって離すと、最後にいた項目が選ばれる', (tester) async {
    final ended = await _pump(tester);
    final gesture = await tester.startGesture(const Offset(20, 30));
    await gesture.moveBy(const Offset(0, 40));
    await gesture.moveBy(const Offset(0, 120));
    await gesture.up();
    expect(ended, [3]);
  });

  testWidgets('項目の下の余白（メニューチップとの間など）では、一番下の項目も選ばれない', (tester) async {
    final ended = await _pump(tester);
    // 項目は縦に0〜300。指を一番下の項目から下の余白へずらして離す。
    final gesture = await tester.startGesture(const Offset(20, 280));
    await gesture.moveBy(const Offset(0, 14));
    await gesture.moveBy(const Offset(0, 100));
    await gesture.up();
    expect(ended, isEmpty);
  });

  testWidgets('余白へ出てから項目の上へ戻って離すと、その項目が選ばれる', (tester) async {
    final ended = await _pump(tester);
    final gesture = await tester.startGesture(const Offset(20, 280));
    await gesture.moveBy(const Offset(0, 114));
    await gesture.moveTo(const Offset(20, 130));
    await gesture.up();
    expect(ended, [2]);
  });

  testWidgets('縦に少し動いてから大きく横へ動いて離しても、選ばれない', (tester) async {
    final ended = await _pump(tester);
    final gesture = await tester.startGesture(const Offset(20, 30));
    await gesture.moveBy(const Offset(0, 14));
    await gesture.moveBy(const Offset(120, 0));
    await gesture.moveBy(const Offset(40, 0));
    await gesture.up();
    expect(ended, isEmpty);
  });

  testWidgets('横だけ動かして離しても、選ばれない', (tester) async {
    final ended = await _pump(tester);
    final gesture = await tester.startGesture(const Offset(20, 30));
    await gesture.moveBy(const Offset(60, 3));
    await gesture.moveBy(const Offset(60, 20));
    await gesture.up();
    expect(ended, isEmpty);
  });

  testWidgets('殆ど動かさずに離した時は、なぞりとして扱わない', (tester) async {
    final ended = await _pump(tester);
    final gesture = await tester.startGesture(const Offset(20, 30));
    await gesture.moveBy(const Offset(2, 4));
    await gesture.up();
    expect(ended, isEmpty);
  });

  testWidgets('チップ列から滑ってきた指（橋渡し）で項目を選べて、外では何も起きない', (tester) async {
    final ended = await _pump(tester);
    final bridge = ProviderScope.containerOf(
      tester.element(find.byType(SlideSelectList)),
    ).read(itemPickBridgeProvider);

    // 一覧の上: 項目2（y=120〜180）。
    final target = bridge.targetAt(const Offset(20, 130));
    expect(target, isNotNull);
    expect(target!.indexAt(const Offset(20, 130)), 2);
    target.pick(2, commit: false);
    await tester.pump();
    target.pick(2, commit: true);
    expect(ended, [2]);

    // 一覧の外（画面の外）は対象にならない。
    expect(bridge.targetAt(const Offset(20, 5000)), isNull);
  });
}

void _bottomAlignTests() {
  Widget host({required CategoryListVertical vertical}) => MaterialApp(
    home: Scaffold(
      body: alignCategoryList(
        vertical: vertical,
        ListView(
          shrinkWrap: true,
          children: [
            for (var i = 0; i < 3; i++)
              SizedBox(height: 60, child: Text('item $i')),
          ],
        ),
      ),
    ),
  );

  testWidgets('下寄せにすると、項目が画面の下端に寄る（並びは変わらない）', (tester) async {
    await tester.pumpWidget(host(vertical: CategoryListVertical.bottom));
    final screenHeight =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    expect(
      tester.getBottomLeft(find.text('item 2')).dy,
      closeTo(screenHeight, 60),
    );
    expect(
      tester.getTopLeft(find.text('item 0')).dy,
      lessThan(tester.getTopLeft(find.text('item 2')).dy),
    );
    expect(tester.getTopLeft(find.text('item 0')).dy, greaterThan(100));
  });

  testWidgets('上寄せ（標準）は、項目が上から並ぶ', (tester) async {
    await tester.pumpWidget(host(vertical: CategoryListVertical.top));
    expect(tester.getTopLeft(find.text('item 0')).dy, lessThan(20));
  });

  testWidgets('中央寄せは、項目が上端・下端どちらからも離れた位置に来る', (tester) async {
    await tester.pumpWidget(host(vertical: CategoryListVertical.center));
    final screenHeight =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    final top = tester.getTopLeft(find.text('item 0')).dy;
    final bottom = tester.getBottomLeft(find.text('item 2')).dy;
    // 上寄せ・下寄せそれぞれの位置より内側（画面の上端にも下端にも寄っていない）。
    expect(top, greaterThan(20));
    expect(bottom, lessThan(screenHeight - 20));
    // 上下の余白がおおよそ等しい（中央揃えらしさの検証）。
    final topGap = top;
    final bottomGap = screenHeight - bottom;
    expect((topGap - bottomGap).abs(), lessThan(20));
  });
}
