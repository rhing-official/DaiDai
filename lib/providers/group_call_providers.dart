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
