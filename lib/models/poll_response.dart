import 'package:cloud_firestore/cloud_firestore.dart';

/// [Poll]1件・住人1人ごとの回答（`.../polls/{pollId}/responses/{uid}`、
/// 2026-09-06追加）。[ScheduleCoordinationResponse]と同じくドキュメントIDを
/// 本人のuidにする。投票は一度きりで、作成後の変更・削除はfirestore.rulesで
/// 禁止している（`allow update: if false; allow delete: if false;`）ため、
/// このクラスにも回答を上書きするメソッドは存在しない。
class PollResponse {
  const PollResponse({
    required this.userId,
    required this.selectedOptionKeys,
    this.respondedAt,
  });

  final String userId;

  /// 選択した[pollOptionKey]の一覧（単一選択でも1要素）。
  final List<String> selectedOptionKeys;
  final Timestamp? respondedAt;

  factory PollResponse.fromJson(String userId, Map<String, dynamic> json) {
    return PollResponse(
      userId: userId,
      selectedOptionKeys: (json['selectedOptionKeys'] as List<dynamic>? ?? [])
          .map((e) => e as String)
          .toList(),
      respondedAt: json['respondedAt'] as Timestamp?,
    );
  }

  Map<String, dynamic> toJson() => {
    'userId': userId,
    'selectedOptionKeys': selectedOptionKeys,
    'respondedAt': respondedAt ?? FieldValue.serverTimestamp(),
  };
}
