import 'package:daidai/widgets/pane_visibility.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

class _Probe extends StatelessWidget {
  const _Probe(this.onBuild);
  final void Function(bool visible) onBuild;

  @override
  Widget build(BuildContext context) {
    onBuild(PaneVisibility.of(context));
    return const SizedBox();
  }
}

void main() {
  testWidgets('包まれていなければ見えている扱い', (tester) async {
    bool? seen;
    await tester.pumpWidget(_Probe((v) => seen = v));
    expect(seen, isTrue);
  });

  testWidgets('入れ子は親との論理積（外側が隠れていれば内側も隠れる）', (tester) async {
    bool? seen;
    Widget tree({required bool outer, required bool inner}) => PaneVisibility(
      visible: outer,
      child: PaneVisibility(visible: inner, child: _Probe((v) => seen = v)),
    );

    await tester.pumpWidget(tree(outer: true, inner: true));
    expect(seen, isTrue);
    await tester.pumpWidget(tree(outer: true, inner: false));
    expect(seen, isFalse);
    await tester.pumpWidget(tree(outer: false, inner: true));
    expect(seen, isFalse);
  });

  testWidgets('IndexedStackの非選択の子は見えない扱いになり、切り替えで追従する', (tester) async {
    final seen = <int, bool>{};
    Widget stack(int index) => IndexedStack(
      index: index,
      textDirection: TextDirection.ltr,
      children: [
        for (var i = 0; i < 2; i++)
          PaneVisibility(
            visible: i == index,
            child: _Probe((v) => seen[i] = v),
          ),
      ],
    );

    await tester.pumpWidget(stack(0));
    expect(seen, {0: true, 1: false});
    await tester.pumpWidget(stack(1));
    expect(seen, {0: false, 1: true});
  });
}
