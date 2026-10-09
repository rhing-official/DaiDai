import 'package:daidai/router/back_stack.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BackStackController', () {
    test('closeTopLayerは最後のエントリが層ならそれだけ閉じ、履歴エントリには触れない', () {
      final c = BackStackController();
      final calls = <String>[];
      c.add(() => calls.add('history'), scope: BackScope.talks);
      c.add(() => calls.add('note'), scope: BackScope.talks, layer: true);
      c.add(() => calls.add('album'), scope: BackScope.talks, layer: true);

      expect(c.closeTopLayer(), isTrue);
      expect(calls, ['album']);
      expect(c.closeTopLayer(), isTrue);
      expect(calls, ['album', 'note']);
      // 残りは層ではない履歴エントリだけ → 閉じず、falseを返す。
      expect(c.closeTopLayer(), isFalse);
      expect(calls, ['album', 'note']);
    });

    test('closeTopLayerはダイアログ（オーバーレイ）を層より先に閉じる', () {
      final c = BackStackController();
      final calls = <String>[];
      c.add(() => calls.add('note'), scope: BackScope.talks, layer: true);
      c.addDialog(() => calls.add('dialog'));

      expect(c.closeTopLayer(), isTrue);
      expect(calls, ['dialog']);
      expect(c.closeTopLayer(), isTrue);
      expect(calls, ['dialog', 'note']);
      expect(c.closeTopLayer(), isFalse);
    });

    test('戻る要求は現在のタブで最後に登録されたエントリのonBackを呼ぶ', () {
      final c = BackStackController();
      final calls = <String>[];
      c.add(() => calls.add('first'), scope: BackScope.talks);
      c.add(() => calls.add('second'), scope: BackScope.talks);

      expect(c.requestBack(), isTrue);
      expect(calls, ['second']);
      expect(c.requestBack(), isTrue);
      expect(calls, ['second', 'first']);
      expect(c.requestBack(), isFalse); // 何も無ければ何もしない
    });

    test('タブをまたいで戻らない（他タブのエントリは対象外）', () {
      final c = BackStackController();
      final calls = <String>[];
      c.add(() => calls.add('talks'), scope: BackScope.talks);
      c.add(() => calls.add('settings'), scope: BackScope.settings);

      c.activeScope = BackScope.profile;
      expect(c.requestBack(), isFalse);
      expect(calls, isEmpty);

      c.activeScope = BackScope.settings;
      expect(c.requestBack(), isTrue);
      expect(calls, ['settings']);
      expect(c.requestBack(), isFalse); // 語らいの履歴には触れない

      c.activeScope = BackScope.talks;
      expect(c.requestBack(), isTrue);
      expect(calls, ['settings', 'talks']);
    });

    test('scopeがnullのエントリはどのタブからでも戻れる', () {
      final c = BackStackController();
      var called = 0;
      c.add(() => called++);
      c.activeScope = BackScope.settings;
      expect(c.requestBack(), isTrue);
      expect(called, 1);
    });

    test('ダイアログが開いていれば、エントリより先にダイアログを閉じる', () {
      final c = BackStackController();
      final calls = <String>[];
      c.add(() => calls.add('entry'), scope: BackScope.talks);
      c.addDialog(() => calls.add('dialog'));

      c.requestBack();
      expect(calls, ['dialog']);
      c.requestBack();
      expect(calls, ['dialog', 'entry']);
    });

    test('closeTopOverlayは開いている最新のオーバーレイだけを閉じる', () {
      final c = BackStackController();
      final calls = <String>[];
      c.add(() => calls.add('entry'), scope: BackScope.talks);
      c.addDialog(() => calls.add('overlay1'));
      c.addDialog(() => calls.add('overlay2'));

      expect(c.closeTopOverlay(), isTrue);
      expect(c.closeTopOverlay(), isTrue);
      expect(c.closeTopOverlay(), isFalse);
      expect(calls, ['overlay2', 'overlay1']); // エントリには触れない
    });

    test('アプリ内操作で閉じたエントリはremoveで外れ、戻る要求の対象にならない', () {
      final c = BackStackController();
      var called = 0;
      final id = c.add(() => called++, scope: BackScope.talks);
      c.remove(id);
      expect(c.requestBack(), isFalse);
      expect(called, 0);
    });

    test('進む要求は直前に戻ったエントリのonForwardをやり直す', () {
      final c = BackStackController();
      final calls = <String>[];
      c.add(
        () => calls.add('back'),
        scope: BackScope.talks,
        onForward: () => calls.add('forward'),
      );

      expect(c.requestForward(), isFalse); // まだ戻っていない
      c.requestBack();
      expect(c.requestForward(), isTrue);
      expect(calls, ['back', 'forward']);
      expect(c.requestForward(), isFalse);
    });

    test('やり直し分はタブごとで、clearRedoで破棄できる', () {
      final c = BackStackController();
      var forwarded = 0;
      c.add(() {}, scope: BackScope.talks, onForward: () => forwarded++);
      c.requestBack();

      c.activeScope = BackScope.settings;
      expect(c.requestForward(), isFalse); // 語らいのやり直しは設定からは使えない

      c.activeScope = BackScope.talks;
      c.clearRedo(BackScope.talks);
      expect(c.requestForward(), isFalse);
      expect(forwarded, 0);
    });

    test('ベースの透明ルートが消えたら戻る要求として処理し、積み直せる状態にする', () {
      final c = BackStackController();
      final pushed = <int>[];
      c.attach(push: pushed.add);
      c.ensureBase();
      expect(pushed, [BackStackController.baseId]);
      expect(c.hasBase, isTrue);

      var called = 0;
      c.add(() => called++, scope: BackScope.talks);
      var notified = 0;
      c.addListener(() => notified++);

      c.onRouteGone(BackStackController.baseId); // ブラウザの戻る
      expect(called, 1);
      expect(c.hasBase, isFalse);
      expect(notified, 1); // BackBaseGuardが積み直す合図

      c.ensureBase();
      expect(pushed, [0, 1]);
      expect(c.isLive(1), isTrue);
    });

    test('複数トークン: 戻っても積み直さず、ブラウザの進むでやり直せる', () {
      final c = BackStackController(tokenCount: 3);
      final pushed = <int>[];
      c.attach(push: pushed.add);
      c.ensureBase();
      expect(pushed, [0, 1, 2]);

      var back = 0;
      var forward = 0;
      c.add(() => back++, scope: BackScope.talks, onForward: () => forward++);
      var notified = 0;
      c.addListener(() => notified++);

      c.onRouteGone(2); // ブラウザの戻る
      expect(back, 1);
      expect(notified, 0); // 積み直さない（進む先を残す）
      expect(pushed, [0, 1, 2]);
      expect(c.isLive(2), isTrue); // 進むで復元されうる

      c.onBrowserForward(2); // ブラウザの進む
      expect(forward, 1);

      c.onBrowserForward(2); // 復元済みのidは無視
      expect(forward, 1);
    });

    test('トークンが尽きたら積み直す（進む先は捨てる）', () {
      final c = BackStackController(tokenCount: 2);
      final pushed = <int>[];
      c.attach(push: pushed.add);
      c.ensureBase();
      var notified = 0;
      c.addListener(() => notified++);
      c.onRouteGone(1);
      c.onRouteGone(0);
      expect(notified, 1);
      c.ensureBase();
      expect(pushed, [0, 1, 2, 3]);
      expect(c.isLive(0), isFalse);
    });
  });

  group('NavHistory', () {
    test('pushで記録し、back/forwardで辿れる', () {
      final h = NavHistory<String>(initial: 'a')
        ..push('b')
        ..push('c');
      expect(h.current, 'c');
      expect(h.back(), 'b');
      expect(h.back(), 'a');
      expect(h.back(), isNull);
      expect(h.canBack, isFalse);
      expect(h.forward(), 'b');
      expect(h.canForward, isTrue);
    });

    test('現在値と同じ値のpushは記録しない', () {
      final h = NavHistory<String>(initial: 'a')..push('a');
      expect(h.length, 1);
    });

    test('戻った後に新しい値をpushするとやり直し分は破棄される', () {
      final h = NavHistory<String>(initial: 'a')
        ..push('b')
        ..push('c');
      h.back();
      h.push('x');
      expect(h.canForward, isFalse);
      expect(h.back(), 'b');
    });

    test('上限を超えた古い履歴は捨てられる', () {
      final h = NavHistory<int>(maxLength: 3, initial: 0);
      for (var i = 1; i <= 5; i++) {
        h.push(i);
      }
      expect(h.length, 3);
      expect(h.back(), 4);
      expect(h.back(), 3);
      expect(h.back(), isNull); // 0〜2へは戻れない
    });

    test('既定の上限は30件', () {
      final h = NavHistory<int>(initial: 0);
      for (var i = 1; i <= 50; i++) {
        h.push(i);
      }
      expect(h.length, kMaxBackHistory);
    });
  });
}
