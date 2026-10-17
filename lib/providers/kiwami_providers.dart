import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../utils/kiwami.dart';
import 'user_providers.dart';

/// [userId]の住人が極みか（2026-10-17追加）。住人データの`subscriptionPlan`を
/// リアルタイムに参照する（付与・解除がすぐ反映される）。
final isKiwamiProvider = Provider.family<bool, String>(
  (ref, userId) => isKiwami(ref.watch(watchedUserProvider(userId)).value),
);

/// 会話の参加者（[idsKey]はuserIdをカンマで連ねた文字列、Familyのキーとして
/// 値比較できるよう呼び出し側でソートして渡す）に、1人でも極みがいるか。
/// 既読機能の無効化は、極みの人がいる間だけ効く（2026-10-17）。
final conversationHasKiwamiProvider = Provider.family<bool, String>((
  ref,
  idsKey,
) {
  for (final id in idsKey.split(',')) {
    if (id.isEmpty) continue;
    if (ref.watch(isKiwamiProvider(id))) return true;
  }
  return false;
});
