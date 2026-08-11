import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/group.dart';
import 'repository_providers.dart';

/// 広場（グループ）のドキュメントをリアルタイムに参照する。ロール管理
/// ポップアップ等、開いている間も`rolePriority`等の変更を反映する必要が
/// ある画面で使う（2026-07-29追加、`user_providers.dart`の
/// `watchedUserProvider`と同じ設計）。
final watchedGroupProvider = StreamProvider.family<Group?, String>((
  ref,
  groupId,
) {
  return ref.watch(groupRepositoryProvider).watchGroup(groupId);
});
