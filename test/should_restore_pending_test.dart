import 'package:daidai/features/auth/auth_gate.dart';
import 'package:daidai/models/saved_account.dart';
import 'package:flutter_test/flutter_test.dart';

/// ログイン画面が開いた時に、保留中のアカウントの追加を捨てて元へ戻すかの判定
/// （2026-11-24）。Webのリダイレクトのログインから戻る途中は、戻さない。
void main() {
  PendingAccountAdd pending({bool continued = false, int expiresAtMs = 1000}) =>
      PendingAccountAdd(
        ticket: 't',
        expiresAtMs: expiresAtMs,
        fromUid: 'a',
        continued: continued,
      );

  test('保留が無ければ戻さない', () {
    expect(shouldRestorePendingAtSignIn(null, 0), isFalse);
  });

  test('印の無い保留（追加の途中で終わった）は、戻す', () {
    expect(shouldRestorePendingAtSignIn(pending(), 500), isTrue);
  });

  test('リダイレクトのログインへ向かう印が有り、期限内なら、戻さない', () {
    expect(
      shouldRestorePendingAtSignIn(pending(continued: true), 1000),
      isFalse,
    );
  });

  test('印が有っても期限が切れていれば、戻す（取り残さない）', () {
    expect(
      shouldRestorePendingAtSignIn(pending(continued: true), 1001),
      isTrue,
    );
  });
}
