import 'package:daidai/widgets/keyboard_stable_body.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 実際のチャット画面と同じく、`Scaffold`はbodyを縮めない設定で使う。
Widget _app(Widget child) => MaterialApp(
  home: Scaffold(
    resizeToAvoidBottomInset: false,
    body: KeyboardStableBody(child: child),
  ),
);

void _useView(WidgetTester tester) {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('キーボードが出ても子の大きさは変わらず、その高さ分だけ上へずれる', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    _useView(tester);

    final key = GlobalKey();
    await tester.pumpWidget(_app(SizedBox.expand(key: key)));
    final closed = tester.getRect(find.byKey(key));
    expect(closed.height, 800);

    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pump();
    final open = tester.getRect(find.byKey(key));
    expect(open.height, 800);
    expect(open.top, -300);

    tester.view.resetViewInsets();
    await tester.pump();
    expect(tester.getRect(find.byKey(key)), closed);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('下の安全領域（ナビゲーションバー分）はずらす量から引く', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    _useView(tester);
    tester.view.viewPadding = const FakeViewPadding(bottom: 24);
    tester.view.padding = const FakeViewPadding(bottom: 24);

    final key = GlobalKey();
    await tester.pumpWidget(_app(SizedBox.expand(key: key)));
    tester.view.viewInsets = const FakeViewPadding(bottom: 324);
    await tester.pump();
    // Scaffoldが縮める時と同じ位置（キーボードの上端に入力欄の下端が付く）になる。
    expect(tester.getRect(find.byKey(key)).top, -300);

    // キーボードが安全領域より低い間は動かさない。
    tester.view.viewInsets = const FakeViewPadding(bottom: 10);
    await tester.pump();
    expect(tester.getRect(find.byKey(key)).top, 0);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('子に見せる下の余白（padding.bottom）は、キーボードが出ても変わらない', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    _useView(tester);
    tester.view.viewPadding = const FakeViewPadding(bottom: 24);
    tester.view.padding = const FakeViewPadding(bottom: 24);

    double? seen;
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) {
            seen = MediaQuery.paddingOf(context).bottom;
            return const SizedBox.expand();
          },
        ),
      ),
    );
    expect(seen, 24);

    // Flutterはキーボードが出るとpadding.bottomを0にする。子には24のまま見せる。
    tester.view.viewInsets = const FakeViewPadding(bottom: 324);
    tester.view.padding = FakeViewPadding.zero;
    await tester.pump();
    expect(seen, 24);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Webやデスクトップ相当では何もしない', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    _useView(tester);

    final key = GlobalKey();
    await tester.pumpWidget(_app(SizedBox.expand(key: key)));
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pump();
    expect(tester.getRect(find.byKey(key)).top, 0);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('キーボードが出入りしても子は作り直されない（状態が保たれる）', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    _useView(tester);

    var created = 0;
    await tester.pumpWidget(_app(_Probe(onInit: () => created++)));
    expect(created, 1);

    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pump();
    tester.view.resetViewInsets();
    await tester.pump();
    tester.view.viewInsets = const FakeViewPadding(bottom: 120);
    await tester.pump();

    expect(created, 1);
    debugDefaultTargetPlatformOverride = null;
  });
}

class _Probe extends StatefulWidget {
  const _Probe({required this.onInit});

  final VoidCallback onInit;

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  void initState() {
    super.initState();
    widget.onInit();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}
