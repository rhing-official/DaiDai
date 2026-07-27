import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/group_call.dart';
import 'repository_providers.dart';

/// その広場で現在進行中の通話（あれば1件）をリアルタイムに参照する。
/// `GroupChatPane`のAppBarで「新規に通話を始める」か「進行中の通話に
/// 参加する」かをボタン押下時に切り替えるために使う。
final activeGroupCallProvider =
    StreamProvider.family<GroupCall?, String>((ref, groupId) {
  return ref.watch(groupCallRepositoryProvider).watchActiveGroupCall(groupId);
});

/// 自分がメンバーになっている広場すべてを横断して、現在進行中の通話一覧を
/// 監視する。着信バナー（[GroupIncomingCallListener]）が新規に始まった
/// 通話を検知するために使う。
final activeGroupCallsForUserProvider =
    StreamProvider.family<List<GroupCall>, String>((ref, userId) {
  return ref
      .watch(groupCallRepositoryProvider)
      .watchActiveGroupCallsForMember(userId);
});
