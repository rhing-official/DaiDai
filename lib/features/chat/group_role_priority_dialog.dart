import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';
import '../../models/group_role.dart';

/// ロールの優先順位（呼び名の色を決める順序、先頭が最優先）をドラッグ＆ドロップで
/// 並べ替えるダイアログ。広場全体の優先順位（`GroupRepository.setRolePriority`）と、
/// 寄合ごとの優先順位上書き（`setRoomRolePriorityOverride`）の両方から共通で使う
/// （2026-07-28追加）。基準ロール（`isEveryone`）は常に最下位固定のため対象外。
class GroupRolePriorityDialog extends StatefulWidget {
  const GroupRolePriorityDialog({
    required this.orderedRoles,
    required this.onSave,
    this.onReset,
    super.key,
  });

  /// 現在の優先順位順に並んだロール一覧（基準ロールは含めない）。
  final List<GroupRole> orderedRoles;

  final ValueChanged<List<String>> onSave;

  /// 非nullなら「広場全体の設定に戻す」ボタンを表示する（寄合ごとの
  /// 優先順位上書きを解除する用途）。
  final VoidCallback? onReset;

  static Future<void> show(
    BuildContext context, {
    required List<GroupRole> orderedRoles,
    required ValueChanged<List<String>> onSave,
    VoidCallback? onReset,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => GroupRolePriorityDialog(
        orderedRoles: orderedRoles,
        onSave: onSave,
        onReset: onReset,
      ),
    );
  }

  @override
  State<GroupRolePriorityDialog> createState() => _GroupRolePriorityDialogState();
}

class _GroupRolePriorityDialogState extends State<GroupRolePriorityDialog> {
  final List<GroupRole> _roles = [];

  @override
  void initState() {
    super.initState();
    _roles.addAll(widget.orderedRoles);
  }

  void _onReorderItem(int index, int newIndex) {
    setState(() {
      final role = _roles.removeAt(index);
      _roles.insert(newIndex, role);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        final strings = ref.watch(appStringsProvider);
        return Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400, maxHeight: 560),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Text(
                    strings.groupRolePriorityTitle,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    strings.groupRolePriorityHint,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const Divider(height: 1),
                Flexible(
                  child: _roles.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            strings.groupRoleListEmpty,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        )
                      : ReorderableListView(
                          shrinkWrap: true,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          onReorderItem: _onReorderItem,
                          children: [
                            for (final role in _roles)
                              ListTile(
                                key: ValueKey(role.roleId),
                                leading: CircleAvatar(
                                  radius: 10,
                                  backgroundColor: role.color != null
                                      ? Color(0xFF000000 | role.color!)
                                      : Colors.transparent,
                                  child: role.color == null
                                      ? const Icon(Icons.circle_outlined, size: 14)
                                      : null,
                                ),
                                title: Text(role.name),
                                trailing: const Icon(Icons.drag_handle),
                              ),
                          ],
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    children: [
                      if (widget.onReset != null)
                        TextButton(
                          onPressed: () {
                            widget.onReset!();
                            Navigator.of(context).pop();
                          },
                          child: Text(strings.groupRoomRolePriorityResetButton),
                        ),
                      const Spacer(),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text(strings.cancel),
                      ),
                      FilledButton(
                        onPressed: () {
                          widget.onSave(_roles.map((r) => r.roleId).toList());
                          Navigator.of(context).pop();
                        },
                        child: Text(strings.save),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
