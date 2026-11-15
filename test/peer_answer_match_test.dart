import 'package:daidai/features/call/peer_answer_match.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('自分の最新のofferへの返事だけを適用する', () {
    expect(shouldApplyAnswer(answerFor: 'a', pendingOfferId: 'a'), isTrue);
    expect(shouldApplyAnswer(answerFor: 'old', pendingOfferId: 'a'), isFalse);
  });

  test('前回の参加の古いanswer（offerをまだ送っていない時）は適用しない', () {
    expect(shouldApplyAnswer(answerFor: 'old', pendingOfferId: null), isFalse);
  });

  test('古い版が書いたanswer（forOfferなし）は従来どおり適用する', () {
    expect(shouldApplyAnswer(answerFor: null, pendingOfferId: 'a'), isTrue);
    expect(shouldApplyAnswer(answerFor: null, pendingOfferId: null), isTrue);
  });

  test('offerのidは毎回違う', () {
    expect(newOfferId(), isNot(newOfferId()));
    expect(newOfferId().length, 12);
  });
}
