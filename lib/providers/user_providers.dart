import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_user.dart';
import 'repository_providers.dart';

/// 他人のプロフィール（アクティブなニックネームなど）をリアルタイムに参照する。
/// 一対一覧・チャット画面のタイトルで、相手のRhing IDの代わりに
/// アクティブなニックネームを表示するために使う。
final watchedUserProvider = StreamProvider.family<AppUser?, String>((
  ref,
  userId,
) {
  return ref.watch(userRepositoryProvider).watchUser(userId);
});
