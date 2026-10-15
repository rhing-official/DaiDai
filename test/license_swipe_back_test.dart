import 'package:daidai/widgets/slide_drilldown.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

NavigatorState? _find(GlobalKey<NavigatorState> key) {
  final root = key.currentContext;
  if (root == null) return null;
  NavigatorState? found;
  void visit(Element e) {
    if (found != null) return;
    if (e is StatefulElement && e.state is NavigatorState) {
      found = e.state as NavigatorState;
      return;
    }
    e.visitChildren(visit);
  }

  (root as Element).visitChildren(visit);
  return found;
}

void main() {
  testWidgets('ライセンスの項目から右スワイプすると、一覧に戻り「アプリについて」へは戻らない', (tester) async {
    final key = GlobalKey<NavigatorState>();
    var backedToAbout = 0;
    bool consume() {
      final n = _find(key);
      if (n == null || !n.canPop()) return false;
      n.pop();
      return true;
    }

    LicenseRegistry.addLicense(() async* {
      yield LicenseEntryWithLineBreaks(['pkg_a'], 'license text A');
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SlideDrilldown(
            master: const Center(child: Text('about')),
            detail: Navigator(
              key: key,
              onGenerateRoute: (_) => MaterialPageRoute<void>(
                builder: (_) => const LicensePage(applicationName: 'DaiDai'),
              ),
            ),
            detailKey: 'licenses',
            onBack: () => backedToAbout++,
            consumeBack: consume,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('pkg_a'));
    await tester.pumpAndSettle();
    expect(find.textContaining('license text A'), findsWidgets);

    final g = await tester.startGesture(const Offset(30, 300));
    await g.moveBy(const Offset(500, 0));
    await tester.pump();
    await g.up();
    await tester.pumpAndSettle();

    expect(backedToAbout, 0, reason: '「アプリについて」へ戻ってはいけない');
    expect(find.text('pkg_a'), findsOneWidget, reason: '一覧が見えている');
    expect(find.textContaining('license text A'), findsNothing);
    expect(tester.getTopLeft(find.byType(LicensePage)).dx, 0);
  });
}
