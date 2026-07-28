import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';
import '../../models/group_role.dart';
import '../../providers/repository_providers.dart';
import '../../utils/color_hex.dart';

/// 広場のカスタムロール一覧（ポップアップの中身）。長・モデレーターのみが
/// 開ける（`_GroupMenuButton`側でメニュー項目自体を無効化する）。名前・色の
/// 作成/編集/削除のみを扱う。メンバーへの付与は`GroupMemberListPopup`側で行う。
class GroupRoleListPopup extends ConsumerWidget {
  const GroupRoleListPopup({required this.groupId, super.key});

  final String groupId;

  Future<void> _showRoleDialog(
    BuildContext context,
    WidgetRef ref,
    Strings strings, {
    GroupRole? existing,
  }) async {
    final nameController = TextEditingController(text: existing?.name ?? '');
    final hexController = TextEditingController(
      text: existing != null
          ? Color(0xFF000000 | existing.color)
              .toHexString()
              .replaceFirst('#', '')
          : 'EE7800',
    );
    String? errorText;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          final previewColor = tryParseHexColor(hexController.text);
          return AlertDialog(
            title: Text(
              existing == null
                  ? strings.groupRoleCreateDialogTitle
                  : strings.groupRoleEditDialogTitle,
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  autofocus: true,
                  decoration:
                      InputDecoration(labelText: strings.groupRoleDialogNameLabel),
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
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: hexController,
                        textCapitalization: TextCapitalization.characters,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp('[0-9a-fA-F]')),
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
                      ),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(strings.cancel),
              ),
              FilledButton(
                onPressed: () {
                  if (nameController.text.trim().isEmpty) return;
                  if (tryParseHexColor(hexController.text) == null) {
                    setState(() => errorText = strings.groupRoleColorInvalid);
                    return;
                  }
                  Navigator.of(context).pop(true);
                },
                child: Text(strings.save),
              ),
            ],
          );
        },
      ),
    );

    if (result != true) return;
    final color = tryParseHexColor(hexController.text)!.toARGB32() & 0xFFFFFF;
    final name = nameController.text.trim();
    final repository = ref.read(groupRepositoryProvider);
    if (existing == null) {
      await repository.createRole(groupId: groupId, name: name, color: color);
    } else {
      await repository.updateRole(
        groupId: groupId,
        roleId: existing.roleId,
        name: name,
        color: color,
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
          .deleteRole(groupId: groupId, roleId: role.roleId);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final groupRepository = ref.watch(groupRepositoryProvider);

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
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add),
                onPressed: () => _showRoleDialog(context, ref, strings),
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
            stream: groupRepository.watchRoles(groupId),
            builder: (context, snapshot) {
              final roles = snapshot.data ?? const <GroupRole>[];
              if (roles.isEmpty) {
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
              return ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 8),
                children: [
                  for (final role in roles)
                    ListTile(
                      leading: CircleAvatar(
                        radius: 12,
                        backgroundColor: Color(0xFF000000 | role.color),
                      ),
                      title: Text(role.name),
                      onTap: () =>
                          _showRoleDialog(context, ref, strings, existing: role),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _confirmDelete(context, ref, strings, role),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}
