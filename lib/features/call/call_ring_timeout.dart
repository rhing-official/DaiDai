import 'package:cloud_firestore/cloud_firestore.dart';

/// 着信に応答しない時、自動で切る（バナー・着信音を止める／一対は不在着信として
/// 終える）までの時間（2026-10-23）。広場の着信バナーと一対の着信の両方で使う。
const kCallRingTimeout = Duration(seconds: 30);

/// 端末の時計のずれの余裕（[isCallRingFresh]）。
const kCallRingClockSkewMargin = Duration(seconds: 30);

/// 着信として鳴らしてよいほど新しい通話か（2026-11-03）。作成から[kCallRingTimeout]
/// （＋時計のずれの余裕）を過ぎた通話は、もう終わっているはずのもの（発信側がタブを
/// 閉じる・圏外になる等で、終了が書かれずに残った）なので、鳴らさない。`createdAt`が
/// 未確定（書き込み直後）の間は新しいとみなす。
bool isCallRingFresh({required Timestamp? createdAt, required DateTime now}) {
  if (createdAt == null) return true;
  return now.difference(createdAt.toDate()) <=
      kCallRingTimeout + kCallRingClockSkewMargin;
}
