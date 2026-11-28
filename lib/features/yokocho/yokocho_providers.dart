import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/sticker.dart';
import '../../providers/repository_providers.dart';

/// 横丁のカタログ（公開中のぺったん、新しい順）。
final yokochoCatalogProvider = StreamProvider<List<StickerPack>>(
  (ref) => ref.watch(yokochoRepositoryProvider).watchCatalog(),
);

/// 自分の所持・お気に入り・カートのid。未ログインの間は空。
final yokochoOwnedIdsProvider = StreamProvider<Set<String>>((ref) {
  final uid = ref.watch(authStateProvider).value?.uid;
  if (uid == null) return Stream.value(const <String>{});
  return ref.watch(yokochoRepositoryProvider).watchOwnedIds(uid);
});

final yokochoFavouriteIdsProvider = StreamProvider<Set<String>>((ref) {
  final uid = ref.watch(authStateProvider).value?.uid;
  if (uid == null) return Stream.value(const <String>{});
  return ref.watch(yokochoRepositoryProvider).watchFavouriteIds(uid);
});

final yokochoCartIdsProvider = StreamProvider<Set<String>>((ref) {
  final uid = ref.watch(authStateProvider).value?.uid;
  if (uid == null) return Stream.value(const <String>{});
  return ref.watch(yokochoRepositoryProvider).watchCartIds(uid);
});
