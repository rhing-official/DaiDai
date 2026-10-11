import '../models/group.dart';
import '../models/group_join_request.dart';

/// 語らい一覧に「承認待ち」として出す参加リクエストだけを返す（2026-10-11追加）。
///
/// 承認されて自分が既にメンバーになった広場（[groups]に同じ`groupId`がある）の
/// リクエストは、承認前のブロックが広場本体と並んで残らないよう除く。同じ広場の
/// 重複も1件にまとめる。
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
