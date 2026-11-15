import 'dart:math';

/// 広場通話のシグナリングで、answerを適用してよいかの判定（2026-11-15）。
///
/// 通話のペアごとのシグナリング情報（`peerLinks`）は、前回の参加の分が残ったまま次の参加でも
/// 使われる。入室の直後に、前回の古いanswerを新しい接続へ適用して`setRemoteDescription`が
/// 失敗し、映像をオフにして接続をやり直すまで受信できなかった。answerには「どのofferへの
/// 返事か」（[answerFor]）を載せ、自分の最新のoffer（[pendingOfferId]）への返事だけを適用する。
///
/// [answerFor]が無い（古い版が書いたanswer）時は、従来どおり適用する。
bool shouldApplyAnswer({
  required String? answerFor,
  required String? pendingOfferId,
}) {
  if (answerFor == null) return true;
  return answerFor == pendingOfferId;
}

/// offerを区別するためのid（送るたびに新しい値）。
String newOfferId() {
  final r = Random.secure();
  return List.generate(12, (_) => r.nextInt(36).toRadixString(36)).join();
}
