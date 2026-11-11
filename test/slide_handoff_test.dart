import 'package:daidai/providers/home_shell_providers.dart';
import 'package:daidai/widgets/pane_visibility.dart';
import 'package:daidai/widgets/slide_select_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// チップ列の代わり。[rect]の上を3等分（縦）した番号を返し、選択の呼び出しを記録する。
class _FakeStrip implements ItemPickTarget {
  _FakeStrip(this.rect);
  final Rect rect;
  final log = <String>[];

  @override
  bool isActiveAt(Offset p) => rect.contains(p);

  @override
  int? indexAt(Offset p) =>
      isActiveAt(p) ? ((p.dy - rect.top) / rect.height * 3).floor() : null;

  @override
  void pick(int? index, {required bool commit}) =>
      log.add('${index ?? 'null'}${commit ? '!' : ''}');
}

class _Harness {
  _Harness(this.tester, this.strip, this.slides, this.ends);
  final WidgetTester tester;
  final _FakeStrip strip;
  final List<int> slides;
  final List<int> ends;
}

/// 左の80pxがチップ列（縦並び）、その右に項目一覧（5項目×60px）。
Future<_Harness> _pump(
  WidgetTester tester, {
  ValueNotifier<bool>? visible,
}) async {
  final slides = <int>[];
  final ends = <int>[];
  final strip = _FakeStrip(const Rect.fromLTWH(0, 0, 80, 300));
  Widget list() => SlideSelectList(
    itemCount: 5,
    onSlide: slides.add,
    onSlideEnd: ends.add,
    builder: (context, keyFor, slidingIndex) => Column(
      children: [
        for (var i = 0; i < 5; i++)
          SizedBox(key: keyFor(i), height: 60, child: Text('item $i')),
      ],
    ),
  );
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              const SizedBox(width: 80),
              Expanded(
                child: visible == null
                    ? list()
                    : ValueListenableBuilder<bool>(
                        valueListenable: visible,
                        builder: (_, v, _) =>
                            PaneVisibility(visible: v, child: list()),
                      ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  ProviderScope.containerOf(
    tester.element(find.byType(SlideSelectList)),
  ).read(itemPickBridgeProvider).register(strip);
  return _Harness(tester, strip, slides, ends);
}

void main() {
  testWidgets('上の項目から真横にチップ列へ滑らせても、チップへ渡り、離すと確定する', (tester) async {
    final h = await _pump(tester);
    final g = await tester.startGesture(const Offset(200, 30));
    await g.moveBy(const Offset(-40, 0));
    await g.moveBy(const Offset(-80, 0));
    await g.moveBy(const Offset(-60, 0)); // x=20、チップ列の上
    await g.up();
    expect(h.strip.log, ['0', '0!']);
    expect(h.ends, isEmpty);
  });

  testWidgets('下の項目から斜めにチップ列へ滑らせても、チップへ渡り、離すと確定する', (tester) async {
    final h = await _pump(tester);
    final g = await tester.startGesture(const Offset(200, 270));
    await g.moveBy(const Offset(-40, -10));
    await g.moveTo(const Offset(40, 150));
    await g.up();
    expect(h.strip.log.last, '1!');
    expect(h.ends, isEmpty);
  });

  testWidgets('チップ列へ出てから項目へ戻って離すと、項目が選ばれ、チップの強調は消える', (tester) async {
    final h = await _pump(tester);
    final g = await tester.startGesture(const Offset(200, 30));
    await g.moveTo(const Offset(40, 30));
    await g.moveTo(const Offset(200, 130));
    await g.up();
    expect(h.strip.log, ['0', 'null']);
    expect(h.ends, [2]);
  });

  testWidgets('チップ列の上でポインターがキャンセルされても、チップの強調は消える', (tester) async {
    final h = await _pump(tester);
    final g = await tester.startGesture(const Offset(200, 30));
    await g.moveTo(const Offset(40, 30));
    await g.cancel();
    expect(h.strip.log.last, 'null');
    expect(h.ends, isEmpty);
  });

  testWidgets('チップ列へ滑らせている途中で一覧が見えなくなっても、チップの強調が残らない', (tester) async {
    final visible = ValueNotifier(true);
    final h = await _pump(tester, visible: visible);
    final g = await tester.startGesture(const Offset(200, 30));
    await g.moveTo(const Offset(40, 30));
    visible.value = false;
    await tester.pump();
    await g.up();
    // 離した時点で、チップは確定されるか強調が消える（飛び出したまま残らない）。
    expect(h.strip.log.last == '0!' || h.strip.log.last == 'null', isTrue);
  });

  testWidgets('一度渡した後の次の操作は、前の渡し先を引きずらない', (tester) async {
    final h = await _pump(tester);
    var g = await tester.startGesture(const Offset(200, 30));
    await g.moveTo(const Offset(40, 30));
    await g.up();
    h.strip.log.clear();
    g = await tester.startGesture(const Offset(200, 90));
    await g.moveBy(const Offset(0, 14));
    await g.moveTo(const Offset(200, 150));
    await g.up();
    expect(h.strip.log, isEmpty);
    expect(h.ends, [2]);
  });
}
