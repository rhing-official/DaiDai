import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_user.dart';
import 'repository_providers.dart';

/// 他人のプロフィール（アクティブなニックネームなど）をリアルタイムに参照する。
/// 一対一覧・チャット画面のタイトルで、相手のRhing Seedの代わりに
/// アクティブなニックネームを表示するために使う。
final watchedUserProvider = StreamProvider.family<AppUser?, String>((
  ref,
  userId,
) {
  return ref.watch(userRepositoryProvider).watchUser(userId);
});

/// 広場のメンバー全員のプロフィールを一括で取得する（`@`メンション候補用、
/// 2026-10-11追加）。引数はFamilyのキーとして値比較できるよう、userIdを
/// ソートしてカンマ区切りにした文字列で渡す。
final usersByIdsProvider = FutureProvider.family<List<AppUser>, String>((
  ref,
  joinedIds,
) {
  final ids = joinedIds.isEmpty ? <String>[] : joinedIds.split(',');
  return ref.read(userRepositoryProvider).getUsersByIds(ids);
});
