import '../models/group.dart';
import '../models/group_join_request.dart';

/// 語らい一覧に「承認待ち」「承認されませんでした」として出す参加リクエストだけを返す
/// （2026-10-11追加、2026-10-13に却下済みも含めた）。
///
/// 承認されて自分が既にメンバーになった広場（[groups]に同じ`groupId`がある）の
/// リクエストは、承認前のブロックが広場本体と並んで残らないよう除く。同じ広場の
/// 重複も1件にまとめる。
/// 自分が送った参加リクエストが、開いている承認待ちの画面から見てどの状態か。
enum JoinRequestOutcome {
  /// 購読がまだ読み込み中（何もしない）。
  loading,

  /// 承認待ち。
  pending,

  /// 却下された。
  declined,

  /// 見つからない（承認されて一覧の対象から外れた、または削除された）。
  /// 承認待ちの画面はもう不要なので閉じる（2026-10-13）。
  gone,
}

/// [requests]（自分の`pending`/`declined`の参加リクエスト。読み込み前はnull）
/// から、[groupId]宛ての申請の状態を判定する。
JoinRequestOutcome joinRequestOutcome(
  List<GroupJoinRequest>? requests,
  String groupId,
) {
  if (requests == null) return JoinRequestOutcome.loading;
  for (final request in requests) {
    if (request.groupId != groupId) continue;
    return request.status == GroupJoinRequestStatus.declined
        ? JoinRequestOutcome.declined
        : JoinRequestOutcome.pending;
  }
  return JoinRequestOutcome.gone;
}

List<GroupJoinRequest> visiblePendingGroupRequests(
  List<GroupJoinRequest> pending,
  List<Group> groups,
) {
  final memberGroupIds = {for (final group in groups) group.groupId};
  final seen = <String>{};
  return [
    for (final request in pending)
      if (!memberGroupIds.contains(request.groupId) &&
          seen.add(request.groupId))
        request,
  ];
}
