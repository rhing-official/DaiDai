import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/direct_message.dart';
import 'repository_providers.dart';

/// 一対（DirectMessage）のドキュメントをリアルタイムに参照する。
/// `DmSettingsPopup`等、開いている間も`roomsEnabled`等の変更を反映する
/// 必要がある画面で使う（`group_providers.dart`の`watchedGroupProvider`と
/// 同じ設計、2026-09-14追加）。
final watchedDmProvider = StreamProvider.family<DirectMessage?, String>((
  ref,
  dmId,
) {
  return ref.watch(directMessageRepositoryProvider).watchDirectMessage(dmId);
});
