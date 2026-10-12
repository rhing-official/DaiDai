import 'package:daidai/features/chat/talks_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Probe extends StatefulWidget {
  const _Probe(this.onInit, this.onDispose);
  final VoidCallback onInit;
  final VoidCallback onDispose;

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
  void dispose() {
    widget.onDispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

// 2026-10-13: 全画面（progress=1）から右スワイプで戻し始めた瞬間にチャット本体が
// 作り直され、ドラッグ中のメッセージ行ごと破棄されて3ブロックへ戻れなかった。
void main() {
  testWidgets('畳み切り↔途中を行き来してもチャット本体は作り直されない', (tester) async {
    final progress = ValueNotifier<double>(1);
    var inits = 0;
    var disposes = 0;
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: buildExpandableChatPane(
          collapseProgress: progress,
          onExpandTap: () => taps++,
          chatPane: _Probe(() => inits++, () => disposes++),
        ),
      ),
    );
    expect(inits, 1);

    // 全画面表示中はタップで全画面化を呼ばない。
    await tester.tap(find.byType(_Probe));
    expect(taps, 0);

    // 戻し始め（1未満）・途中・開き切りでも同じStateのまま。
    for (final v in [0.8, 0.4, 0.0, 0.6, 1.0]) {
      progress.value = v;
      await tester.pump();
    }
    expect(inits, 1);
    expect(disposes, 0);

    // 途中（プレビュー中）はタップで全画面化を呼ぶ。
    progress.value = 0.3;
    await tester.pump();
    await tester.tap(find.byType(_Probe));
    expect(taps, 1);
  });
}
