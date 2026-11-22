import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daidai/repositories/auth_repository.dart';

void main() {
  test('Appleの再認証を閉じた・取り消した場合は、取り消しとみなす', () {
    for (final code in [
      'canceled',
      'web-context-canceled',
      'popup-closed-by-user',
      'user-cancelled',
    ]) {
      expect(
        isAppleReauthCancelled(FirebaseAuthException(code: code)),
        isTrue,
        reason: code,
      );
    }
  });

  test('それ以外の失敗・FirebaseAuthException以外は、取り消しではない', () {
    expect(
      isAppleReauthCancelled(
        FirebaseAuthException(code: 'network-request-failed'),
      ),
      isFalse,
    );
    expect(isAppleReauthCancelled(StateError('x')), isFalse);
  });
}
