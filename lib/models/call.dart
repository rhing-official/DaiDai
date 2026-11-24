import 'package:cloud_firestore/cloud_firestore.dart';

/// 通話の状態。
/// ringing: 発信中・着信中（まだ応答されていない）
/// active: 通話中
/// ended / declined / missed: 終了状態
enum CallStatus {
  ringing,
  active,
  ended,
  declined,
  missed;

  static CallStatus fromName(String name) {
    return CallStatus.values.firstWhere(
      (status) => status.name == name,
      orElse: () => CallStatus.ended,
    );
  }
}

/// 通話（1対1の一対内でのみ利用。音声・ビデオ両対応、[isVideo]で区別する）。
class Call {
  const Call({
    required this.callId,
    required this.dmId,
    required this.callerId,
    required this.callerRhingSeed,
    required this.calleeId,
    required this.calleeRhingSeed,
    required this.status,
    this.isVideo = false,
    this.callerIsVideo = false,
    this.calleeIsVideo = false,
    this.offer,
    this.answer,
    this.createdAt,
    this.endedAt,
    this.connectedAt,
    this.callerSeenAt,
    this.calleeSeenAt,
    this.answeredBy,
    this.roomId,
    this.urgent = false,
  });

  final String callId;

  /// この通話が属する一対のid。通話終了後、通話履歴メッセージをどの語らいに
  /// 投稿するか特定する為に使う（`WebrtcCallController`参照）。
  final String dmId;

  /// 通話を始めた寄合のid（表示用、2026-11-18）。変更前に始まった通話はnull。
  final String? roomId;

  /// 緊急の発信か（2026-11-25）。受け手の端末のおやすみモードを貫通して鳴らす（Androidで、受け手が
  /// 端末の「おやすみモードの許可」を与えている時だけ）。
  final bool urgent;
  final String callerId;
  final String callerRhingSeed;
  final String calleeId;
  final String calleeRhingSeed;
  final CallStatus status;

  /// 通話開始時点の種別（true: 720pビデオ通話、false: 音声のみ通話）。
  /// 開始後は[callerIsVideo]/[calleeIsVideo]がそれぞれ独立に変化しうる為、
  /// これは「最初に選んだ種別」の記録としてのみ使う（通話履歴の種別表示等）。
  final bool isVideo;

  /// 通話中の音声⇔ビデオ切替は、切り替えた本人側にのみ適用される
  /// （相手が強制的に切り替わることは無い）。そのため発信者・着信者
  /// それぞれの現在の種別を別フィールドで持つ。
  final bool callerIsVideo;
  final bool calleeIsVideo;
  final Map<String, dynamic>? offer;
  final Map<String, dynamic>? answer;
  final Timestamp? createdAt;
  final Timestamp? endedAt;

  /// 応答した時刻（通話時間の計算用、2026-11-17。古い通話には無い）。
  final Timestamp? connectedAt;

  /// 通話中に各端末が15秒ごとに書く時刻（生きている通話かの判定用、2026-11-17）。
  /// 古いクライアントの通話・今回の変更前に残った通話には無い。
  final Timestamp? callerSeenAt;
  final Timestamp? calleeSeenAt;

  /// 応答を始めた端末のセッションid（同じアカウントの別端末の着信を止めるため。未応答はnull）。
  final String? answeredBy;

  String otherRhingSeed(String currentUserId) {
    return currentUserId == callerId ? calleeRhingSeed : callerRhingSeed;
  }

  /// 自分側のRhing Seed（[otherRhingSeed]の逆、通話画面で自分のアバターを出す時に使う）。
  String myRhingSeed(String currentUserId) {
    return currentUserId == callerId ? callerRhingSeed : calleeRhingSeed;
  }

  String otherUserId(String currentUserId) {
    return currentUserId == callerId ? calleeId : callerId;
  }

  factory Call.fromJson(String callId, Map<String, dynamic> json) {
    final legacyIsVideo = json['isVideo'] as bool? ?? false;
    return Call(
      callId: callId,
      dmId: json['dmId'] as String? ?? '',
      callerId: json['callerId'] as String,
      callerRhingSeed: json['callerRhingSeed'] as String,
      calleeId: json['calleeId'] as String,
      calleeRhingSeed: json['calleeRhingSeed'] as String,
      status: CallStatus.fromName(json['status'] as String),
      isVideo: legacyIsVideo,
      callerIsVideo: json['callerIsVideo'] as bool? ?? legacyIsVideo,
      calleeIsVideo: json['calleeIsVideo'] as bool? ?? legacyIsVideo,
      offer: (json['offer'] as Map?)?.cast<String, dynamic>(),
      answer: (json['answer'] as Map?)?.cast<String, dynamic>(),
      createdAt: json['createdAt'] as Timestamp?,
      endedAt: json['endedAt'] as Timestamp?,
      connectedAt: json['connectedAt'] as Timestamp?,
      callerSeenAt: json['callerSeenAt'] as Timestamp?,
      calleeSeenAt: json['calleeSeenAt'] as Timestamp?,
      answeredBy: json['answeredBy'] as String?,
      roomId: json['roomId'] as String?,
      urgent: json['urgent'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'dmId': dmId,
      if (roomId != null) 'roomId': roomId,
      if (urgent) 'urgent': true,
      'callerId': callerId,
      'callerRhingSeed': callerRhingSeed,
      'calleeId': calleeId,
      'calleeRhingSeed': calleeRhingSeed,
      'status': status.name,
      'isVideo': isVideo,
      'callerIsVideo': callerIsVideo,
      'calleeIsVideo': calleeIsVideo,
      'offer': offer,
      'answer': answer,
      'createdAt': createdAt ?? FieldValue.serverTimestamp(),
      'endedAt': endedAt,
    };
  }
}

/// 通話中のハートビートが途絶えたとみなす時間（広場の`kGroupCallPresenceStaleAfter`と同じ）。
const kCallPresenceStaleAfter = Duration(seconds: 45);

/// ハートビートを一度も書いていない通話（古いクライアント・変更前の残骸）を、生きているとみなす
/// 最大の時間。これを超えて`active`のままの通話は、終了が書かれず残ったものとして扱う。
const kCallNoHeartbeatMaxAge = Duration(hours: 3);

/// 一対の通話（`active`）が、まだ生きているか（2026-11-17）。語らい一覧の「通話中」の標を、
/// 終了が書かれずに残った通話に出さないための判定。サーバーの`sweepStaleCalls`も同じ基準
/// （ハートビートは余裕を持たせて90秒）で終わらせる。
bool isOneToOneCallLive(Call call, DateTime now) {
  if (call.status != CallStatus.active) return false;
  final seen = [
    call.callerSeenAt,
    call.calleeSeenAt,
  ].whereType<Timestamp>().map((t) => t.toDate()).toList();
  if (seen.isNotEmpty) {
    return seen.any((t) => now.difference(t) <= kCallPresenceStaleAfter);
  }
  final since = (call.connectedAt ?? call.createdAt)?.toDate();
  if (since == null) return true; // 書き込み直後など、時刻が未確定
  return now.difference(since) <= kCallNoHeartbeatMaxAge;
}

/// 与えた通話の一覧の中に、今まさに生きている一対の通話が1件でもあるか
/// （発信前に「相手は既に通話中か」を確かめる用、2026-11-23）。
bool anyOneToOneCallLive(List<Call> calls, DateTime now) =>
    calls.any((call) => isOneToOneCallLive(call, now));
