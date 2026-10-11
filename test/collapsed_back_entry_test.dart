import 'package:daidai/router/back_stack.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// 全画面（畳んだ状態）を戻る操作で元へ戻す（2026-10-12）。
void main() {
  testWidgets('閾値を超えている間だけ戻る要求を受け、onBackが呼ばれる', (tester) async {
    final controller = BackStackController();
    final progress = ValueNotifier<double>(0);
    var backs = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [backStackControllerProvider.overrideWithValue(controller)],
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: CollapsedBackEntry(
            progress: progress,
            scope: BackScope.talks,
            onBack: () => backs++,
            child: const SizedBox(),
          ),
        ),
      ),
    );
    await tester.pump();

    // 開いている間は何も登録されない。
    expect(controller.depthOf(BackScope.talks), 0);
    expect(controller.requestBack(), isFalse);

    // 畳むと戻る要求を受ける。
    progress.value = 1;
    await tester.pump();
    await tester.pump();
    expect(controller.depthOf(BackScope.talks), 1);
    expect(controller.requestBack(), isTrue);
    expect(backs, 1);

    // 開き直したら外れる。
    progress.value = 0.2;
    await tester.pump();
    await tester.pump();
    expect(controller.depthOf(BackScope.talks), 0);
  });
}
