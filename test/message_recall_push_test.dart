import 'package:daidai/push_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('送信取消の合図だけを判定する', () {
    expect(isMessageRecallPush({'type': 'message_recalled'}), isTrue);
    expect(isMessageRecallPush({'type': 'call_cancel'}), isFalse);
    expect(isMessageRecallPush({'title': 'x'}), isFalse);
  });

  test('通知idはメッセージidから決まり、同じidなら同じ値（負にならない）', () {
    final a = messageNotificationId('msg-1', 7);
    expect(a, messageNotificationId('msg-1', 99));
    expect(a, isNot(messageNotificationId('msg-2', 7)));
    expect(a, greaterThanOrEqualTo(0));
  });

  test('メッセージidが無い古い通知は従来の値', () {
    expect(messageNotificationId(null, 7), 7);
    expect(messageNotificationId('', 7), 7);
  });
}
