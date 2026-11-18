import 'package:daidai/models/call.dart';
import 'package:daidai/repositories/call_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('応答を書いてよいのは、呼び出し中と通話中だけ（終了済みには書かない）', () {
    expect(canWriteAnswer(CallStatus.ringing), isTrue);
    expect(canWriteAnswer(CallStatus.active), isTrue);
    expect(canWriteAnswer(CallStatus.ended), isFalse);
    expect(canWriteAnswer(CallStatus.declined), isFalse);
    expect(canWriteAnswer(CallStatus.missed), isFalse);
  });
}
