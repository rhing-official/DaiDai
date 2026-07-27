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
    required this.callerRhingId,
    required this.calleeId,
    required this.calleeRhingId,
    required this.status,
    this.isVideo = false,
    this.callerIsVideo = false,
    this.calleeIsVideo = false,
    this.offer,
    this.answer,
    this.createdAt,
    this.endedAt,
  });

  final String callId;

  /// この通話が属する一対のid。通話終了後、通話履歴メッセージをどの語らいに
  /// 投稿するか特定するために使う（`WebrtcCallController`参照）。
  final String dmId;
  final String callerId;
  final String callerRhingId;
  final String calleeId;
  final String calleeRhingId;
  final CallStatus status;

  /// 通話開始時点の種別（true: 720pビデオ通話、false: 音声のみ通話）。
  /// 開始後は[callerIsVideo]/[calleeIsVideo]がそれぞれ独立に変化しうるため、
  /// これは「最初に選んだ種別」の記録としてのみ使う（通話履歴の種別表示等）。
  final bool isVideo;

  /// 通話中の音声⇔ビデオ切替は、切り替えた本人側にのみ適用される
  /// （相手が強制的に切り替わることはない）。そのため発信者・着信者
  /// それぞれの現在の種別を別フィールドで持つ。
  final bool callerIsVideo;
  final bool calleeIsVideo;
  final Map<String, dynamic>? offer;
  final Map<String, dynamic>? answer;
  final Timestamp? createdAt;
  final Timestamp? endedAt;

  String otherRhingId(String currentUserId) {
    return currentUserId == callerId ? calleeRhingId : callerRhingId;
  }

  factory Call.fromJson(String callId, Map<String, dynamic> json) {
    final legacyIsVideo = json['isVideo'] as bool? ?? false;
    return Call(
      callId: callId,
      dmId: json['dmId'] as String? ?? '',
      callerId: json['callerId'] as String,
      callerRhingId: json['callerRhingId'] as String,
      calleeId: json['calleeId'] as String,
      calleeRhingId: json['calleeRhingId'] as String,
      status: CallStatus.fromName(json['status'] as String),
      isVideo: legacyIsVideo,
      callerIsVideo: json['callerIsVideo'] as bool? ?? legacyIsVideo,
      calleeIsVideo: json['calleeIsVideo'] as bool? ?? legacyIsVideo,
      offer: (json['offer'] as Map?)?.cast<String, dynamic>(),
      answer: (json['answer'] as Map?)?.cast<String, dynamic>(),
      createdAt: json['createdAt'] as Timestamp?,
      endedAt: json['endedAt'] as Timestamp?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'dmId': dmId,
      'callerId': callerId,
      'callerRhingId': callerRhingId,
      'calleeId': calleeId,
      'calleeRhingId': calleeRhingId,
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
