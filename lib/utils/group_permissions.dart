import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';

import '../models/group.dart';
import '../models/group_role.dart';

/// [userId]が広場[group]で[permission]（[GroupPermission]の定数）を持つか。
/// 長（[Group.ownerId]）は常に全権限を持つ。それ以外は[Group.memberPermissions]
/// （ロールの権限・付与から`GroupRepository`が非正規化して計算した実効権限）を見る。
///
/// UI側の権限ゲートは全てこの関数を通す（firestore.rulesも同じ
/// `memberPermissions`を根拠にしており、判定結果を一致させるため）。
bool hasGroupPermission({
  required Group group,
  required String userId,
  required String permission,
}) {
  if (group.ownerId == userId) return true;
  return group.memberPermissions[userId]?.contains(permission) ?? false;
}

/// この寄合で実際に使う既読機能のオン/オフを解決する。[room]の
/// `customSettingsEnabled`がtrueかつ`readReceiptsEnabledOverride`が
/// 設定されていればそちらを、それ以外は[group]全体の`readReceiptsEnabled`
/// を使う（2026-07-29追加）。
bool effectiveReadReceiptsEnabled({required Group group, Room? room}) {
  if (room?.customSettingsEnabled ?? false) {
    return room?.readReceiptsEnabledOverride ?? group.readReceiptsEnabled;
  }
  return group.readReceiptsEnabled;
}

/// この寄合で「加入前のメッセージを新規メンバーに見せる」かを解決する
/// （2026-10-08追加）。[room]の`customSettingsEnabled`がtrueかつ
/// `historyVisibleOverride`が設定されていればそちらを、それ以外は[group]全体の
/// `historyVisibleToNewMembers`を使う。firestore.rulesの`historyVisible`と
/// 同じ判定にしておくこと。
bool effectiveHistoryVisible({required Group group, Room? room}) {
  if (room?.customSettingsEnabled ?? false) {
    return room?.historyVisibleOverride ?? group.historyVisibleToNewMembers;
  }
  return group.historyVisibleToNewMembers;
}

/// [userId]がこの寄合で閲覧できるメッセージの最古時刻（`sentAt >= この値`）。
/// nullなら制限なし（加入時刻の記録が無い既存メンバー・長、または履歴を見せる
/// 設定）。メッセージ取得クエリへそのまま`where`として渡す（firestore.rulesの
/// `list`は、クエリ自体が条件を満たす絞り込みを持たないと拒否されるため）。
Timestamp? messageVisibleFrom({
  required Group group,
  required Room? room,
  required String userId,
}) {
  final joinedAt = group.memberJoinedAt[userId];
  if (joinedAt == null) return null;
  if (effectiveHistoryVisible(group: group, room: room)) return null;
  return joinedAt;
}

/// 送信者[userId]の呼び名に適用するフォントカラーを解決する。
/// [currentRoom]の`customSettingsEnabled`がtrueの間だけ
/// `rolePriorityOverride`を、それ以外は[group]の`rolePriority`を使い、
/// 優先順位の高い方から見て色を持つ最初の付与ロールの色を採用する。
/// どの付与ロールにも色が無ければ基準ロール（[GroupRole.isEveryone]）の色
/// （あれば）を使う。該当が無ければnull（呼び出し側は既定色にフォールバック
/// する）。
Color? resolveSenderColor({
  required Group group,
  required Room? currentRoom,
  required List<GroupRole> roles,
  required String userId,
}) {
  final rolesById = {for (final role in roles) role.roleId: role};
  final assignedIds = group.roleAssignments[userId] ?? const <String>[];
  if (assignedIds.isEmpty) {
    return _everyoneColor(roles);
  }

  final useOverride = currentRoom?.customSettingsEnabled ?? false;
  final priority = useOverride
      ? (currentRoom?.rolePriorityOverride ?? group.rolePriority)
      : group.rolePriority;
  for (final roleId in priority) {
    if (!assignedIds.contains(roleId)) continue;
    final role = rolesById[roleId];
    if (role?.color != null) {
      return Color(0xFF000000 | role!.color!);
    }
  }

  // 優先順位リストに載っていない付与ロール（作成直後など）も、色を持つ
  // ものがあれば拾う。無ければ基準ロールの色にフォールバックする。
  for (final roleId in assignedIds) {
    if (priority.contains(roleId)) continue;
    final role = rolesById[roleId];
    if (role?.color != null) {
      return Color(0xFF000000 | role!.color!);
    }
  }

  return _everyoneColor(roles);
}

Color? _everyoneColor(List<GroupRole> roles) {
  final everyone = roles.firstWhereOrNull((r) => r.isEveryone);
  final color = everyone?.color;
  return color != null ? Color(0xFF000000 | color) : null;
}
