import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';
import '../../models/app_user.dart';
import '../../models/group.dart';
import '../../models/group_role.dart';
import '../../providers/group_providers.dart';
import '../../providers/repository_providers.dart';
import '../../utils/color_hex.dart';
import 'group_role_priority_dialog.dart';

/// 広場のカスタムロール一覧（ポップアップの中身）。`manageRoles`権限を持つ
/// メンバーのみが開ける（`_GroupMenuButton`側でメニュー項目自体を無効化する）。
/// 名前・色・権限の作成/編集・優先順位の並べ替えに加え、このロールを付与する
/// メンバーの選択もここで行える（基準ロールを除く。メンバー起点での付与・解除は
/// 引き続き`GroupMemberListPopup`側からも行える）。[group]は優先順位
/// （`rolePriority`）の表示・初期値に使う。
class GroupRoleListPopup extends ConsumerWidget {
  const GroupRoleListPopup({
    required this.currentUser,
    required this.group,
    super.key,
  });

  final AppUser currentUser;
  final Group group;

  Future<void> _showRoleDialog(
    BuildContext context,
    WidgetRef ref,
    Strings strings,
    Group group, {
    GroupRole? existing,
  }) async {
    final nameController = TextEditingController(text: existing?.name ?? '');
    final hexController = TextEditingController(
      text: existing?.color != null
          ? Color(
              0xFF000000 | existing!.color!,
            ).toHexString().replaceFirst('#', '')
          : 'EE7800',
    );
    var hasColor = existing?.color != null;
    final permissions = {...?existing?.permissions};
    final isEveryone = existing?.isEveryone ?? false;
    String? errorText;

    // 基準ロール（全員に自動適用）はメンバーを個別に選ぶ意味が無いため取得しない。
    final members = isEveryone
        ? <AppUser>[]
        : await ref.read(userRepositoryProvider).getUsersByIds(group.memberIds);
    members.sort((a, b) => a.rhingId.compareTo(b.rhingId));
    final initiallyAssignedIds = existing == null
        ? const <String>{}
        : {
            for (final member in members)
              if (group.roleAssignments[member.userId]?.contains(
                    existing.roleId,
                  ) ??
                  false)
                member.userId,
          };
    final selectedMemberIds = {...initiallyAssignedIds};

    if (!context.mounted) return;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          final previewColor = hasColor
              ? tryParseHexColor(hexController.text)
              : null;
          void confirm() {
            if (!isEveryone && nameController.text.trim().isEmpty) return;
            if (hasColor && tryParseHexColor(hexController.text) == null) {
              setState(() => errorText = strings.groupRoleColorInvalid);
              return;
            }
            Navigator.of(context).pop(true);
          }

          return AlertDialog(
            title: Text(
              existing == null
                  ? strings.groupRoleCreateDialogTitle
                  : strings.groupRoleEditDialogTitle,
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isEveryone) ...[
                    Text(
                      strings.groupRoleEveryoneNote,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextField(
                    controller: nameController,
                    autofocus: !isEveryone,
                    enabled: !isEveryone,
                    decoration: InputDecoration(
                      labelText: strings.groupRoleDialogNameLabel,
                    ),
                    onSubmitted: (_) => confirm(),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        margin: const EdgeInsets.only(top: 4),
                        decoration: BoxDecoration(
                          color: previewColor ?? Colors.transparent,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.black12),
                        ),
                        child: previewColor == null
                            ? const Icon(Icons.circle_outlined, size: 18)
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: hexController,
                          enabled: hasColor,
                          textCapitalization: TextCapitalization.characters,
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp('[0-9a-fA-F]'),
                            ),
                            LengthLimitingTextInputFormatter(6),
                          ],
                          decoration: InputDecoration(
                            labelText: strings.settingsColorCode,
                            prefixText: '#',
                            hintText: 'EE7800',
                            errorText: errorText,
                            counterText: '',
                          ),
                          onChanged: (_) => setState(() {}),
                          onSubmitted: (_) => confirm(),
                        ),
                      ),
                    ],
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: !hasColor,
                    title: Text(strings.groupRoleColorNone),
                    onChanged: (checked) =>
                        setState(() => hasColor = !(checked ?? false)),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    strings.groupRolePermissionsLabel,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  for (final permission in GroupPermission.all)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: permissions.contains(permission),
                      title: Text(strings.groupPermissionLabel(permission)),
                      onChanged: (checked) => setState(() {
                        if (checked ?? false) {
                          permissions.add(permission);
                        } else {
                          permissions.remove(permission);
                        }
                      }),
                    ),
                  if (!isEveryone) ...[
                    const SizedBox(height: 8),
                    Text(
                      strings.groupRoleMembersLabel,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value:
                          members.isNotEmpty &&
                          selectedMemberIds.length == members.length,
                      title: Text(strings.groupRoleAssignAllLabel),
                      onChanged: members.isEmpty
                          ? null
                          : (checked) => setState(() {
                              if (checked ?? false) {
                                selectedMemberIds.addAll(
                                  members.map((m) => m.userId),
                                );
                              } else {
                                selectedMemberIds.clear();
                              }
                            }),
                    ),
                    for (final member in members)
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: selectedMemberIds.contains(member.userId),
                        secondary: CircleAvatar(
                          radius: 14,
                          backgroundImage: member.effectiveIcon?.url != null
                              ? NetworkImage(member.effectiveIcon!.url)
                              : null,
                          child: member.effectiveIcon?.url == null
                              ? const Icon(Icons.person, size: 16)
                              : null,
                        ),
                        title: Text(
                          (member.effectiveNickname?.text.isNotEmpty ?? false)
                              ? member.effectiveNickname!.text
                              : '@${member.rhingId}',
                        ),
                        onChanged: (checked) => setState(() {
                          if (checked ?? false) {
                            selectedMemberIds.add(member.userId);
                          } else {
                            selectedMemberIds.remove(member.userId);
                          }
                        }),
                      ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(strings.cancel),
              ),
              FilledButton(onPressed: confirm, child: Text(strings.save)),
            ],
          );
        },
      ),
    );

    if (result != true) return;
    final color = hasColor
        ? tryParseHexColor(hexController.text)!.toARGB32() & 0xFFFFFF
        : null;
    final name = isEveryone ? existing!.name : nameController.text.trim();
    final repository = ref.read(groupRepositoryProvider);
    String roleId;
    if (existing == null) {
      final created = await repository.createRole(
        groupId: group.groupId,
        name: name,
        color: color,
        permissions: permissions,
      );
      roleId = created.roleId;
    } else {
      await repository.updateRole(
        groupId: group.groupId,
        roleId: existing.roleId,
        name: name,
        color: color,
        permissions: permissions,
      );
      roleId = existing.roleId;
    }

    // 権限の有無に関わらず、選んだメンバーには付与する（色だけの見た目専用
    // ロールを全員に付与するといった使い方も成立させるため）。
    final addedIds = selectedMemberIds.difference(initiallyAssignedIds);
    final removedIds = initiallyAssignedIds.difference(selectedMemberIds);
    for (final userId in addedIds) {
      await repository.assignRole(
        groupId: group.groupId,
        userId: userId,
        roleId: roleId,
      );
    }
    for (final userId in removedIds) {
      await repository.unassignRole(
        groupId: group.groupId,
        userId: userId,
        roleId: roleId,
      );
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Strings strings,
    GroupRole role,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings.groupRoleDeleteConfirmTitle),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(strings.groupRoleDeleteConfirmButton),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref
          .read(groupRepositoryProvider)
          .deleteRole(
            groupId: group.groupId,
            roleId: role.roleId,
            requestedBy: currentUser.userId,
          );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final groupRepository = ref.watch(groupRepositoryProvider);
    // widget.groupはこのポップアップを開いた時点の静的なスナップショットで、
    // 開いたまま優先順位ダイアログ等で`rolePriority`を変更しても自動更新
    // されない（ロールの並び順を変更したのに反映されない不具合の原因、
    // 2026-07-29発覚・修正）。ライブな値をここでwatchして使う。
    final liveGroup =
        ref.watch(watchedGroupProvider(group.groupId)).value ?? group;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 4, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  strings.groupMenuManageRoles,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add),
                onPressed: () =>
                    _showRoleDialog(context, ref, strings, liveGroup),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Flexible(
          child: StreamBuilder<List<GroupRole>>(
            stream: groupRepository.watchRoles(liveGroup.groupId),
            builder: (context, snapshot) {
              final allRoles = snapshot.data ?? const <GroupRole>[];
              if (allRoles.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    strings.groupRoleListEmpty,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                );
              }
              final everyone = allRoles.firstWhereOrNull((r) => r.isEveryone);
              final regularUnsorted = allRoles
                  .where((r) => !r.isEveryone)
                  .toList();
              final fallbackIndex = regularUnsorted.length;
              final regular = regularUnsorted
                ..sort((a, b) {
                  final indexA = liveGroup.rolePriority.indexOf(a.roleId);
                  final indexB = liveGroup.rolePriority.indexOf(b.roleId);
                  // rolePriorityに無いロール（作成直後の反映待ち等）は末尾扱い。
                  return (indexA == -1 ? fallbackIndex : indexA).compareTo(
                    indexB == -1 ? fallbackIndex : indexB,
                  );
                });
              return ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 8),
                children: [
                  if (regular.isNotEmpty)
                    ListTile(
                      dense: true,
                      title: Text(
                        strings.groupRolePriorityHint,
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.swap_vert),
                        tooltip: strings.groupRolePriorityTitle,
                        onPressed: () => GroupRolePriorityDialog.show(
                          context,
                          orderedRoles: regular,
                          onSave: (roleIds) => groupRepository.setRolePriority(
                            groupId: liveGroup.groupId,
                            roleIds: roleIds,
                          ),
                        ),
                      ),
                    ),
                  for (final role in regular)
                    ListTile(
                      leading: CircleAvatar(
                        radius: 12,
                        backgroundColor: role.color != null
                            ? Color(0xFF000000 | role.color!)
                            : Colors.transparent,
                        child: role.color == null
                            ? const Icon(Icons.circle_outlined, size: 16)
                            : null,
                      ),
                      title: Text(role.name),
                      onTap: () => _showRoleDialog(
                        context,
                        ref,
                        strings,
                        liveGroup,
                        existing: role,
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () =>
                            _confirmDelete(context, ref, strings, role),
                      ),
                    ),
                  if (everyone != null) ...[
                    const Divider(height: 16),
                    ListTile(
                      leading: CircleAvatar(
                        radius: 12,
                        backgroundColor: everyone.color != null
                            ? Color(0xFF000000 | everyone.color!)
                            : Colors.transparent,
                        child: everyone.color == null
                            ? const Icon(Icons.circle_outlined, size: 16)
                            : null,
                      ),
                      title: Text(everyone.name),
                      onTap: () => _showRoleDialog(
                        context,
                        ref,
                        strings,
                        liveGroup,
                        existing: everyone,
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}
