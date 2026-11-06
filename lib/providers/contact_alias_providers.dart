import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'repository_providers.dart';

/// 自分が相手に指定した呼び名（相手のuserId→呼び名、2026-11-06）。ログインしていない間は空。
/// 表示側が自分のIDを渡さずに済むよう、認証状態のuidから購読する。
final myContactAliasesProvider = StreamProvider<Map<String, String>>((ref) {
  final uid = ref.watch(authStateProvider).value?.uid;
  if (uid == null) return Stream.value(const <String, String>{});
  return ref.watch(contactAliasRepositoryProvider).watchAliases(uid);
});
