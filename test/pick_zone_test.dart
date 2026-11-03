import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:daidai/providers/home_shell_providers.dart';
import 'package:daidai/widgets/pane_visibility.dart';
import 'package:daidai/widgets/pick_zone.dart';

void main() {
  Future<({List<String> log, ItemPickBridge bridge})> pump(
    WidgetTester tester, {
    bool visible = true,
  }) async {
    final log = <String>[];
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: PaneVisibility(
              visible: visible,
              child: Align(
                alignment: Alignment.topLeft,
                child: PickZone(
                  onEnter: () => log.add('enter'),
                  onCommit: () => log.add('commit'),
                  child: const SizedBox(width: 100, height: 50),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final bridge = ProviderScope.containerOf(
      tester.element(find.byType(PickZone)),
    ).read(itemPickBridgeProvider);
    return (log: log, bridge: bridge);
  }

  testWidgets('指が乗ると強調してonEnter、離すとonCommit', (tester) async {
    final r = await pump(tester);
    final target = r.bridge.targetAt(const Offset(20, 20));
    expect(target, isNotNull);
    expect(target!.indexAt(const Offset(20, 20)), 0);
    target.pick(0, commit: false);
    target.pick(0, commit: false); // 2回目は何も起きない
    await tester.pump();
    target.pick(0, commit: true);
    expect(r.log, ['enter', 'commit']);
  });

  testWidgets('領域の外・非表示の画面では対象にならない', (tester) async {
    final r = await pump(tester);
    expect(r.bridge.targetAt(const Offset(400, 400)), isNull);
    final hidden = await pump(tester, visible: false);
    expect(hidden.bridge.targetAt(const Offset(20, 20)), isNull);
  });

  testWidgets('PickZoneを押した指を別のPickZoneへ滑らせて離すと、そちらがonCommit', (tester) async {
    final log = <String>[];
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                PickZone(
                  onEnter: () => log.add('a-enter'),
                  onCommit: () => log.add('a-commit'),
                  child: const SizedBox(width: 100, height: 50),
                ),
                PickZone(
                  onEnter: () => log.add('b-enter'),
                  onCommit: () => log.add('b-commit'),
                  child: const SizedBox(width: 100, height: 50),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    // 元の部品の上で離す（ふつうのタップ）: 何も呼ばない。
    var g = await tester.startGesture(const Offset(20, 20));
    await g.moveBy(const Offset(5, 0));
    await g.up();
    expect(log, isEmpty);
    // 別の部品へ滑らせて離す。
    g = await tester.startGesture(const Offset(20, 20));
    await g.moveTo(const Offset(150, 20));
    await tester.pump();
    await g.up();
    expect(log, ['b-enter', 'b-commit']);
  });

  testWidgets('行って戻る往復でも、毎回onEnterが呼ばれる', (tester) async {
    final log = <String>[];
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                PickZone(
                  onEnter: () => log.add('a'),
                  onCommit: () => log.add('a-commit'),
                  child: const SizedBox(width: 100, height: 50),
                ),
                PickZone(
                  onEnter: () => log.add('b'),
                  onCommit: () => log.add('b-commit'),
                  child: const SizedBox(width: 100, height: 50),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final g = await tester.startGesture(const Offset(20, 20));
    await g.moveTo(const Offset(150, 20));
    await g.moveTo(const Offset(20, 20));
    await g.moveTo(const Offset(150, 20));
    await g.moveTo(const Offset(20, 20));
    await g.up();
    expect(log, ['b', 'a', 'b', 'a']);
  });
}
