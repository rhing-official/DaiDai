import 'package:daidai/utils/user_activity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final activity = UserActivity.instance;
  setUp(activity.debugReset);

  test('直近の操作が有れば、操作中と判定する', () {
    activity.debugRecord(DateTime.now().millisecondsSinceEpoch);
    expect(activity.touchedWithin(const Duration(seconds: 3)), isTrue);
  });

  test('古い操作は、操作中に数えない', () {
    activity.debugRecord(
      DateTime.now().millisecondsSinceEpoch - 10000,
    );
    expect(activity.touchedWithin(const Duration(seconds: 3)), isFalse);
  });

  test('自分の終話ボタンの操作は、捨てられる', () {
    activity.debugRecord(DateTime.now().millisecondsSinceEpoch - 8000);
    activity.debugRecord(DateTime.now().millisecondsSinceEpoch - 200);
    activity.forgetRecent();
    expect(activity.touchedWithin(const Duration(seconds: 3)), isFalse);
  });

  test('入力欄の下書きの有無', () {
    final owner = Object();
    ComposerDraftTracker.set(owner, true);
    expect(ComposerDraftTracker.hasDraft, isTrue);
    ComposerDraftTracker.set(owner, false);
    expect(ComposerDraftTracker.hasDraft, isFalse);
  });
}
