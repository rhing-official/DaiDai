import 'package:daidai/widgets/gekiga/gekiga_panel_box.dart';
import 'package:daidai/widgets/swipe_gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

enum _Cat { dm, group }

class _Probe extends StatefulWidget {
  const _Probe({this.initialCategory = _Cat.dm});
  final _Cat initialCategory;
  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  late _Cat _category = widget.initialCategory;

  void _setCategory(_Cat c) => setState(() => _category = c);

  // 一対は件数が多く縦スクロールが必要（ビューポートより長い）、
  // 広場は件数が少なくスクロール不要（実際のユーザー報告の状況を再現）。
  Widget _buildDm() {
    final children = [
      for (var i = 0; i < 30; i++) SizedBox(height: 56, child: Text('dm-$i')),
    ];
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GekigaJointedTileList(
        seeds: [for (var i = 0; i < children.length; i++) i],
        selectedFlags: [for (var i = 0; i < children.length; i++) false],
        children: children,
      ),
    );
  }

  Widget _buildGroup() {
    final children = [
      for (var i = 0; i < 2; i++) SizedBox(height: 56, child: Text('group-$i')),
    ];
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GekigaJointedTileList(
        seeds: [for (var i = 0; i < children.length; i++) i],
        selectedFlags: [for (var i = 0; i < children.length; i++) false],
        children: children,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Scaffold(
        body: Column(
          children: [
            Text(_category == _Cat.dm ? 'DM' : 'GROUP'),
            Expanded(
              child: SwipeBackDetector(
                onBack: () {},
                onPrevious: () => _setCategory(_Cat.dm),
                onNext: () => _setCategory(_Cat.group),
                child: _category == _Cat.dm ? _buildDm() : _buildGroup(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void main() {
  testWidgets('縦スクロールが必要な一対リストの上で、わずかに斜めの左スワイプをすると広場へ切り替わらない', (tester) async {
    tester.view.physicalSize = const Size(800, 400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: _Probe()));
    expect(find.text('DM'), findsOneWidget);

    // 実際の指でのスワイプは完全に水平ではない。縦方向にも動くとする
    // （水平300pxに対し縦40px程度、fling()で現実的な速度・タイムスタンプを
    // 再現する）。
    await tester.fling(find.text('dm-0'), const Offset(-300, 40), 1000);
    await tester.pumpAndSettle();

    expect(find.text('GROUP'), findsOneWidget);
  });

  testWidgets('スクロール不要な短い広場リストの上では、同じ斜めの右スワイプで一対へ切り替わる（対照実験）', (tester) async {
    tester.view.physicalSize = const Size(800, 400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(home: _Probe(initialCategory: _Cat.group)),
    );
    expect(find.text('GROUP'), findsOneWidget);

    await tester.fling(find.text('group-0'), const Offset(300, 40), 1000);
    await tester.pumpAndSettle();

    expect(find.text('DM'), findsOneWidget);
  });

  testWidgets('縦方向優位の純粋なスクロールでは誤ってカテゴリが切り替わらない（回帰ガード）', (tester) async {
    tester.view.physicalSize = const Size(800, 400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: _Probe()));
    expect(find.text('DM'), findsOneWidget);

    await tester.fling(find.text('dm-0'), const Offset(0, -300), 1000);
    await tester.pumpAndSettle();

    expect(find.text('DM'), findsOneWidget);
  });
}
