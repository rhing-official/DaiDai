import 'package:daidai/features/call/active_call_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('通話中の通知のタップ: 通話が無ければ開かない', () {
    expect(shouldReopenCallFromNotification(null), isFalse);
  });
}
