import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/group_join_request.dart';
import 'repository_providers.dart';

/// 自分が送った、承認待ち・却下済みの広場参加リクエスト一覧（語らいタブの
/// 広場一覧に「申請中」「承認されませんでした」として表示するために使う）。
final myGroupJoinRequestsProvider =
    StreamProvider.family<List<GroupJoinRequest>, String>((ref, userId) {
      return ref.watch(groupRepositoryProvider).watchMyJoinRequests(userId);
    });

/// 広場の承認待ちの参加リクエスト一覧（2026-10-11追加）。読み取りは長・
/// `manageJoinRequests`権限者のみ許可されている（firestore.rules）ため、
/// 権限を確認した広場でだけ購読すること。バナー・語らい一覧のバッジが共有する。
final pendingJoinRequestsProvider =
    StreamProvider.family<List<GroupJoinRequest>, String>((ref, groupId) {
      return ref.watch(groupRepositoryProvider).watchJoinRequests(groupId);
    });
