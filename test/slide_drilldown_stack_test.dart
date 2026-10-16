import 'package:daidai/widgets/slide_drilldown.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// 戻った先の階層が、右から再度スライドインしない（Stateも保たれる）ことの回帰テスト。
class _Counter extends StatefulWidget {
  const _Counter(this.label);
  final String label;
  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  static int created = 0;
  @override
  void initState() {
    super.initState();
    created++;
  }

  @override
  Widget build(BuildContext context) => Center(child: Text(widget.label));
}

Widget _app(List<String> keys, void Function(String) onBack) => MaterialApp(
  home: Scaffold(
    body: SizedBox(
      width: 400,
      height: 800,
      child: SlideDrilldownStack(
        base: const Text('base'),
        layers: [
          for (final k in keys)
            DrilldownLayer(key: k, child: _Counter(k), onBack: () => onBack(k)),
        ],
      ),
    ),
  ),
);

void main() {
  testWidgets('最上位を外しても、下の階層は再生成・再スライドされない', (tester) async {
    _CounterState.created = 0;
    await tester.pumpWidget(_app(['a', 'b'], (_) {}));
    await tester.pumpAndSettle();
    expect(_CounterState.created, 2);
    final before = tester.getTopLeft(find.text('a'));

    await tester.pumpWidget(_app(['a'], (_) {}));
    // 再スライドするなら、最初のフレームで右へずれる。
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.getTopLeft(find.text('a')), before);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('a')), before);
    expect(_CounterState.created, 2);
    expect(find.text('b'), findsNothing);
  });

  testWidgets('右スワイプで最上位だけが動き、直下の階層が見える', (tester) async {
    final backed = <String>[];
    await tester.pumpWidget(_app(['a', 'b'], backed.add));
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(const Offset(200, 400));
    await gesture.moveBy(const Offset(100, 0));
    await gesture.moveBy(const Offset(100, 0));
    await tester.pump();
    final mid = tester.getTopLeft(find.text('b')).dx;
    expect(tester.getTopLeft(find.text('b')).dx, greaterThan(100));
    final a = find.text('a');
    expect(a, findsOneWidget);
    expect(tester.getTopLeft(a).dx, lessThan(400));
    // 確定のしきい値は画面幅（テストでは800）の40%。
    await gesture.moveBy(const Offset(200, 0));
    await tester.pump();
    expect(tester.getTopLeft(find.text('b')).dx, greaterThan(mid));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(backed, ['b']);
  });
}
