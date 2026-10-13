import 'package:daidai/features/call/disconnect_grace.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('切断が猶予を超えて続くと終了を通知する', () {
    fakeAsync((async) {
      var expired = 0;
      final grace = DisconnectGrace(onExpired: () => expired++);
      grace.update(true);
      async.elapse(const Duration(seconds: 7));
      expect(expired, 0);
      async.elapse(const Duration(seconds: 2));
      expect(expired, 1);
    });
  });

  test('猶予内に回復すれば終了しない', () {
    fakeAsync((async) {
      var expired = 0;
      final grace = DisconnectGrace(onExpired: () => expired++);
      grace.update(true);
      async.elapse(const Duration(seconds: 5));
      grace.update(false);
      async.elapse(const Duration(seconds: 10));
      expect(expired, 0);
      expect(grace.isWaiting, isFalse);
    });
  });
}
