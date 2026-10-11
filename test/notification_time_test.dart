import 'package:daidai/models/message_time_format.dart';
import 'package:daidai/utils/message_time.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 10, 11, 15, 0);

  test('同じ日は時刻のみ', () {
    expect(
      formatNotificationTime(
        DateTime(2026, 10, 11, 9, 5),
        now,
        MessageTimeFormat.h24,
      ),
      '09:05',
    );
  });

  test('日を跨いだら月/日が付く（年は付かない）', () {
    expect(
      formatNotificationTime(
        DateTime(2026, 10, 10, 23, 59),
        now,
        MessageTimeFormat.h24,
      ),
      '10/10 23:59',
    );
  });

  test('年を跨いだら西暦4桁の年も付く', () {
    expect(
      formatNotificationTime(
        DateTime(2025, 12, 31, 23, 59),
        now,
        MessageTimeFormat.h24,
      ),
      '2025/12/31 23:59',
    );
  });

  test('12時間表記でも同じ出し分けになる', () {
    expect(
      formatNotificationTime(
        DateTime(2026, 10, 11, 14, 32),
        now,
        MessageTimeFormat.h12,
      ),
      '2:32 p.m.',
    );
    expect(
      formatNotificationTime(
        DateTime(2025, 1, 2, 0, 7),
        now,
        MessageTimeFormat.h12,
      ),
      '2025/1/2 12:07 a.m.',
    );
  });
}
