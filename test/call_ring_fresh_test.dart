import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:daidai/features/call/call_ring_timeout.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 11, 3, 12, 0, 0);
  Timestamp ago(Duration d) => Timestamp.fromDate(now.subtract(d));

  test('isCallRingFresh: 書き込み直後（createdAt未確定）は新しい', () {
    expect(isCallRingFresh(createdAt: null, now: now), isTrue);
  });

  test('isCallRingFresh: 呼び出し時間内（＋時計のずれの余裕）は新しい', () {
    expect(
      isCallRingFresh(createdAt: ago(const Duration(seconds: 10)), now: now),
      isTrue,
    );
    expect(
      isCallRingFresh(createdAt: ago(const Duration(seconds: 59)), now: now),
      isTrue,
    );
  });

  test('isCallRingFresh: それより古い通話は鳴らさない', () {
    expect(
      isCallRingFresh(createdAt: ago(const Duration(minutes: 2)), now: now),
      isFalse,
    );
    expect(
      isCallRingFresh(createdAt: ago(const Duration(hours: 1)), now: now),
      isFalse,
    );
  });
}
