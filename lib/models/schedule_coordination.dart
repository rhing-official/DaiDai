import 'package:cloud_firestore/cloud_firestore.dart';

/// 日程調整への回答の選択肢（○/△/×、2026-09-05追加）。
enum ScheduleCoordinationVote {
  yes,
  maybe,
  no;

  static ScheduleCoordinationVote? fromName(String? name) {
    for (final vote in ScheduleCoordinationVote.values) {
      if (vote.name == name) return vote;
    }
    return null;
  }
}

/// 寄合単位の日程調整（複数の候補日を提案し、参加者が候補ごとに○/△/×で
/// 回答する機能、2026-09-05追加。`directMessages/{dmId}/rooms/{roomId}/
/// scheduleCoordinations/{coordinationId}`または`groups/{groupId}/rooms/
/// {roomId}/scheduleCoordinations/{coordinationId}`）。
///
/// [CalendarEvent]の参加確認（RSVP）機能と同じ設計を踏襲する。回答は
/// [ScheduleCoordinationResponse]（`responses`サブコレクション）に分離。
/// 投票後の確定は自動では行わず、作成者が候補の中から1つを選んで通常の
/// 予定追加フォームを開き、実際の[CalendarEvent]として作成した上で
/// [finalizedCandidateIndex]/[finalizedEventId]を書き込む
/// （`schedule_coordination_detail_dialog.dart`参照）。確定後は投票を
/// 締め切り、読み取り専用表示に切り替える。
class ScheduleCoordination {
  const ScheduleCoordination({
    required this.coordinationId,
    required this.roomId,
    required this.title,
    this.description,
    required this.candidateDates,
    required this.createdBy,
    this.createdAt,
    this.deadline,
    this.responseCount = 0,
    this.finalizedCandidateIndex,
    this.finalizedEventId,
  });

  final String coordinationId;
  final String roomId;
  final String title;
  final String? description;

  /// 候補日（日付のみ、00:00に揃えて保存する）。時刻は確定後の予定追加
  /// フォームで別途指定する（2026-09-05方針）。
  final List<Timestamp> candidateDates;
  final String createdBy;
  final Timestamp? createdAt;

  /// 回答期限。[CalendarEvent.rsvpDeadline]と同じ意味論（nullなら期限なし、
  /// 過ぎると新規回答・回答変更ともfirestore.rulesで拒否される）。
  final Timestamp? deadline;

  /// 回答済み住人の人数（非正規化カウンタ、[CalendarEvent.rsvpCount]と同じ
  /// 仕組み。新規回答作成時のみ+1）。
  final int responseCount;

  /// 確定した候補の配列index。未確定なら null。[finalizedEventId]と必ず
  /// 同時にセットされ、一度セットされたら変更不可（firestore.rules参照）。
  final int? finalizedCandidateIndex;

  /// 確定によって作成された[CalendarEvent.eventId]。未確定ならnull。
  final String? finalizedEventId;

  bool get isFinalized => finalizedEventId != null;

  factory ScheduleCoordination.fromJson(
    String coordinationId,
    Map<String, dynamic> json,
  ) {
    return ScheduleCoordination(
      coordinationId: coordinationId,
      roomId: json['roomId'] as String,
      title: json['title'] as String,
      description: json['description'] as String?,
      candidateDates: (json['candidateDates'] as List<dynamic>)
          .map((e) => e as Timestamp)
          .toList(),
      createdBy: json['createdBy'] as String,
      createdAt: json['createdAt'] as Timestamp?,
      deadline: json['deadline'] as Timestamp?,
      responseCount: json['responseCount'] as int? ?? 0,
      finalizedCandidateIndex: json['finalizedCandidateIndex'] as int?,
      finalizedEventId: json['finalizedEventId'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'roomId': roomId,
    'title': title,
    'description': description,
    'candidateDates': candidateDates,
    'createdBy': createdBy,
    'createdAt': createdAt ?? FieldValue.serverTimestamp(),
    'deadline': deadline,
    'responseCount': responseCount,
    'finalizedCandidateIndex': finalizedCandidateIndex,
    'finalizedEventId': finalizedEventId,
  };
}

/// [ScheduleCoordinationResponse.votes]のキー形式。候補は配列indexで識別する
/// （2026-09-05追加）。日付文字列をキーにすると、同じ日付の候補が複数
/// 登録された場合（作成UIでは弾いているが、データ上は起こり得る）に
/// 投票先が衝突してしまうため、常に安定した配列indexを使う。
String scheduleCoordinationCandidateKey(int index) => '$index';
