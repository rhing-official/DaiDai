import 'package:daidai/router/back_stack.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Host extends StatefulWidget {
  const _Host({required this.scope, this.layer = false});

  final BackScope scope;
  final bool layer;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  int _value = 0;

  @override
  Widget build(BuildContext context) {
    return NavHistoryBackEntry<int>(
      scope: widget.scope,
      layer: widget.layer,
      location: _value,
      onRestore: (v) => setState(() => _value = v),
      child: Column(
        children: [
          Text('value=$_value'),
          TextButton(
            onPressed: () => setState(() => _value++),
            child: const Text('inc'),
          ),
        ],
      ),
    );
  }
}

void main() {
  testWidgets('位置の移り変わりを記録し、戻る・進むで復元できる', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(backStackControllerProvider);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: _Host(scope: BackScope.settings)),
        ),
      ),
    );
    controller.activeScope = BackScope.settings;
    await tester.pump();

    // 初期位置(0)の後に1→2と移動する。
    await tester.tap(find.text('inc'));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('inc'));
    await tester.pump();
    await tester.pump();
    expect(find.text('value=2'), findsOneWidget);

    expect(controller.requestBack(), isTrue);
    await tester.pump();
    await tester.pump();
    expect(find.text('value=1'), findsOneWidget);

    expect(controller.requestBack(), isTrue);
    await tester.pump();
    await tester.pump();
    expect(find.text('value=0'), findsOneWidget);

    // これ以上は戻れない（初期位置）。
    expect(controller.requestBack(), isFalse);

    // 進む（デスクトップのマウスの進むボタン相当）。
    expect(controller.requestForward(), isTrue);
    await tester.pump();
    await tester.pump();
    expect(find.text('value=1'), findsOneWidget);

    // 新しい操作をすると、やり直し分は消える。
    await tester.tap(find.text('inc'));
    await tester.pump();
    await tester.pump();
    expect(find.text('value=2'), findsOneWidget);
    expect(controller.requestForward(), isFalse);
  });

  testWidgets('別のタブがアクティブな間は、このタブの履歴を戻さない', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(backStackControllerProvider);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: _Host(scope: BackScope.talks)),
        ),
      ),
    );
    await tester.tap(find.text('inc'));
    await tester.pump();
    await tester.pump();

    controller.activeScope = BackScope.settings;
    expect(controller.requestBack(), isFalse);
    expect(find.text('value=1'), findsOneWidget);
  });

  testWidgets('layer: trueの履歴は、closeTopLayerで1つ戻り、尽きたらfalse（ルートを閉じる）', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(backStackControllerProvider);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: _Host(scope: BackScope.talks, layer: true)),
        ),
      ),
    );
    await tester.tap(find.text('inc'));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('inc'));
    await tester.pump();
    await tester.pump();
    expect(find.text('value=2'), findsOneWidget);

    expect(controller.closeTopLayer(), isTrue);
    await tester.pump();
    await tester.pump();
    expect(find.text('value=1'), findsOneWidget);

    expect(controller.closeTopLayer(), isTrue);
    await tester.pump();
    await tester.pump();
    expect(find.text('value=0'), findsOneWidget);

    // 履歴が尽きたら戻さない（呼び出し側がルートごと閉じる）。
    expect(controller.closeTopLayer(), isFalse);
    expect(find.text('value=0'), findsOneWidget);
  });

  testWidgets('layerを指定しない履歴は、closeTopLayerでは戻さない（従来どおり）', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(backStackControllerProvider);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: _Host(scope: BackScope.talks)),
        ),
      ),
    );
    await tester.tap(find.text('inc'));
    await tester.pump();
    await tester.pump();

    expect(controller.closeTopLayer(), isFalse);
    expect(find.text('value=1'), findsOneWidget);
  });
}
