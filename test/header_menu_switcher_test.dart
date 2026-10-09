import 'package:daidai/features/chat/button_anchored_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// ヘッダーのドロップダウンを開いたまま別のボタンを押すと、メニューを閉じて
/// そのボタンの操作が実行されること（2026-10-10追加）の検証。
class _Header extends StatefulWidget {
  const _Header({required this.log});
  final List<String> log;
  @override
  State<_Header> createState() => _HeaderState();
}

class _HeaderState extends State<_Header> {
  final _keyA = GlobalKey();
  final _keyB = GlobalKey();
  final _keyC = GlobalKey();
  VoidCallback? _unregisterA;
  VoidCallback? _unregisterB;
  VoidCallback? _unregisterC;

  @override
  void initState() {
    super.initState();
    _unregisterA = registerHeaderMenuTrigger(
      context,
      _keyA,
      () => _open('A', _keyA),
    );
    _unregisterB = registerHeaderMenuTrigger(
      context,
      _keyB,
      () => _open('B', _keyB),
    );
    _unregisterC = registerHeaderMenuTrigger(
      context,
      _keyC,
      () => widget.log.add('C'),
    );
  }

  @override
  void dispose() {
    _unregisterA?.call();
    _unregisterB?.call();
    _unregisterC?.call();
    super.dispose();
  }

  Future<void> _open(String name, GlobalKey key) async {
    widget.log.add('open $name');
    final box = key.currentContext!.findRenderObject()! as RenderBox;
    final bottomLeft = box.localToGlobal(Offset(0, box.size.height));
    await showAnchoredMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(bottomLeft.dx, bottomLeft.dy, 0, 0),
      anchorKey: key,
      items: [PopupMenuItem<String>(value: name, child: Text('menu $name'))],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        actions: [
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    key: _keyA,
                    icon: const Icon(Icons.looks_one),
                    onPressed: () => _open('A', _keyA),
                  ),
                  IconButton(
                    key: _keyB,
                    icon: const Icon(Icons.looks_two),
                    onPressed: () => _open('B', _keyB),
                  ),
                  IconButton(
                    key: _keyC,
                    icon: const Icon(Icons.looks_3),
                    onPressed: () => widget.log.add('C'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      body: const Center(child: Text('body')),
    );
  }
}

Future<void> _pump(WidgetTester tester, List<String> log) async {
  await tester.pumpWidget(
    MaterialApp(
      home: ChatScrollGuardScope(
        beginPopup: () {},
        endPopup: () {},
        menuSwitcher: HeaderMenuSwitcher(),
        child: _Header(log: log),
      ),
    ),
  );
}

Finder _iconButton(IconData icon) => find.widgetWithIcon(IconButton, icon);

void main() {
  testWidgets('メニューAを開いたままボタンBを押すと、Aが閉じてBのメニューが開く', (tester) async {
    final log = <String>[];
    await _pump(tester, log);
    await tester.tap(_iconButton(Icons.looks_one));
    await tester.pumpAndSettle();
    expect(find.text('menu A'), findsOneWidget);

    await tester.tap(_iconButton(Icons.looks_two), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('menu A'), findsNothing);
    expect(find.text('menu B'), findsOneWidget);
    expect(log, ['open A', 'open B']);
  });

  testWidgets('メニュー表示中に非メニューのボタンCを押すと、閉じてCの操作が実行される', (tester) async {
    final log = <String>[];
    await _pump(tester, log);
    await tester.tap(_iconButton(Icons.looks_one));
    await tester.pumpAndSettle();

    await tester.tap(_iconButton(Icons.looks_3), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('menu A'), findsNothing);
    expect(log, ['open A', 'C']);
  });

  testWidgets('自分のボタンを押すと閉じるだけ（開き直さない）', (tester) async {
    final log = <String>[];
    await _pump(tester, log);
    await tester.tap(_iconButton(Icons.looks_one));
    await tester.pumpAndSettle();

    await tester.tap(_iconButton(Icons.looks_one), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('menu A'), findsNothing);
    expect(log, ['open A']);
  });

  testWidgets('メニュー外のボタン以外の場所を押すと閉じるだけ', (tester) async {
    final log = <String>[];
    await _pump(tester, log);
    await tester.tap(_iconButton(Icons.looks_one));
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(20, 400));
    await tester.pumpAndSettle();
    expect(find.text('menu A'), findsNothing);
    expect(log, ['open A']);
  });

  testWidgets('FittedBoxで縮小されたヘッダー列でも、見た目の位置のボタンに当たる', (tester) async {
    tester.view.physicalSize = const Size(120, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final log = <String>[];
    await _pump(tester, log);
    await tester.tap(_iconButton(Icons.looks_one));
    await tester.pumpAndSettle();

    await tester.tap(_iconButton(Icons.looks_two), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('menu B'), findsOneWidget);
  });

  test('isSameItemPosition', () {
    expect(
      isSameItemPosition(
        indexA: 0,
        leadingEdgeA: 0.1,
        indexB: 0,
        leadingEdgeB: 0.1005,
      ),
      isTrue,
    );
    expect(
      isSameItemPosition(
        indexA: 0,
        leadingEdgeA: 0.1,
        indexB: 0,
        leadingEdgeB: 0.2,
      ),
      isFalse,
    );
    expect(
      isSameItemPosition(
        indexA: 1,
        leadingEdgeA: 0.1,
        indexB: 0,
        leadingEdgeB: 0.1,
      ),
      isFalse,
    );
  });
}
