import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/group_join_request.dart';
import 'repository_providers.dart';

/// 自分が送った、承認待ちの広場参加リクエスト一覧（語らいタブの広場一覧に
/// 「申請中」として表示するために使う）。
final myPendingGroupJoinRequestsProvider =
    StreamProvider.family<List<GroupJoinRequest>, String>((ref, userId) {
  return ref
      .watch(groupRepositoryProvider)
      .watchMyPendingJoinRequests(userId);
});
