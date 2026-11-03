import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/group_role.dart';
import '../utils/group_permissions.dart';
import 'group_providers.dart';

/// 広場の通話で、[userId]がBGMを流せるか（`GroupPermission.playBgm`、2026-11-03）。
/// 広場の情報を読み込めるまではfalse。
final canPlayCallBgmProvider =
    Provider.family<bool, ({String groupId, String userId})>((ref, key) {
      final group = ref.watch(watchedGroupProvider(key.groupId)).value;
      if (group == null) return false;
      return hasGroupPermission(
        group: group,
        userId: key.userId,
        permission: GroupPermission.playBgm,
      );
    });
