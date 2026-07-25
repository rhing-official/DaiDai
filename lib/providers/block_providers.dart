import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'repository_providers.dart';

/// 自分がブロックした相手のuserId一覧。
final blockedUserIdsProvider =
    StreamProvider.family<Set<String>, String>((ref, userId) {
  return ref.watch(blockRepositoryProvider).watchBlockedUserIds(userId);
});
