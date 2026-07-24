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
    required this.callerId,
    required this.callerRhingId,
    required this.calleeId,
    required this.calleeRhingId,
    required this.status,
    this.isVideo = false,
    this.offer,
    this.answer,
    this.createdAt,
    this.endedAt,
  });

  final String callId;
  final String callerId;
  final String callerRhingId;
  final String calleeId;
  final String calleeRhingId;
  final CallStatus status;

  /// true: 720pビデオ通話、false: 音声のみ通話。
  final bool isVideo;
  final Map<String, dynamic>? offer;
  final Map<String, dynamic>? answer;
  final Timestamp? createdAt;
  final Timestamp? endedAt;

  String otherRhingId(String currentUserId) {
    return currentUserId == callerId ? calleeRhingId : callerRhingId;
  }

  factory Call.fromJson(String callId, Map<String, dynamic> json) {
    return Call(
      callId: callId,
      callerId: json['callerId'] as String,
      callerRhingId: json['callerRhingId'] as String,
      calleeId: json['calleeId'] as String,
      calleeRhingId: json['calleeRhingId'] as String,
      status: CallStatus.fromName(json['status'] as String),
      isVideo: json['isVideo'] as bool? ?? false,
      offer: (json['offer'] as Map?)?.cast<String, dynamic>(),
      answer: (json['answer'] as Map?)?.cast<String, dynamic>(),
      createdAt: json['createdAt'] as Timestamp?,
      endedAt: json['endedAt'] as Timestamp?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'callerId': callerId,
      'callerRhingId': callerRhingId,
      'calleeId': calleeId,
      'calleeRhingId': calleeRhingId,
      'status': status.name,
      'isVideo': isVideo,
      'offer': offer,
      'answer': answer,
      'createdAt': createdAt ?? FieldValue.serverTimestamp(),
      'endedAt': endedAt,
    };
  }
}
