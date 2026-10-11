import 'package:daidai/models/direct_message.dart';
import 'package:flutter_test/flutter_test.dart';

// 絶縁の拒否記録（2026-10-11）。既存の一対（フィールド欠落）はnullとして読める。
void main() {
  Map<String, dynamic> json() => {
    'participants': ['a', 'b'],
    'participantRhingSeeds': {'a': 'a', 'b': 'b'},
  };

  test('フィールド欠落はnull', () {
    expect(DirectMessage.fromJson('a_b', json()).severanceDeclinedBy, isNull);
  });

  test('拒否した人のuserIdを読み書きできる', () {
    final dm = DirectMessage.fromJson('a_b', {
      ...json(),
      'severanceDeclinedBy': 'b',
    });
    expect(dm.severanceDeclinedBy, 'b');
    expect(dm.toJson()['severanceDeclinedBy'], 'b');
  });
}
