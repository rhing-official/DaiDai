import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';
import '../../models/group.dart';
import '../../models/group_role.dart';
import '../../providers/group_providers.dart';
import '../../providers/repository_providers.dart';
import '../../utils/group_permissions.dart';

const _kRowHeight = 48.0;
const _kHeaderHeight = 56.0;
const _kLabelWidth = 190.0;
const _kFixedColumnWidth = 72.0;
const _kRoleColumnWidth = 96.0;

/// ポップアップの最小幅と、ダイアログの左右余白（`Dialog`既定の40×2）。
const _kMinWidth = 360.0;
const _kDialogInset = 80.0;

/// 広場の権限を「権限×ロール」の一覧表で確認・編集するダイアログ
/// （2026-10-10追加）。ロールごとの編集ダイアログの中にしか無かった権限を一覧に
/// し、特に全メンバーに最初から付く基準ロール（[GroupRole.isEveryone]、
/// デフォルト権限）が何を許可しているかをひと目で分かるようにする。
/// 左側に権限名・長（常に全権限）・全員の列を固定し、カスタムロールの列だけを
/// 横スクロールにする。セルの切り替えは即時に保存する
/// （`GroupPermission.managePermissions`を持つメンバーのみ編集できる）。
class GroupPermissionManagePopup extends ConsumerWidget {
  const GroupPermissionManagePopup({
    required this.group,
    required this.currentUserId,
    super.key,
  });

  final Group group;

  /// 操作しているメンバー。`managePermissions`を持つ場合だけセルを編集できる
  /// （持たなければ閲覧のみ、2026-10-11）。
  final String currentUserId;

  Future<void> _toggle(
    WidgetRef ref,
    GroupRole role,
    String permission,
    bool allowed,
  ) {
    final permissions = {...role.permissions};
    if (allowed) {
      permissions.add(permission);
    } else {
      permissions.remove(permission);
    }
    return ref
        .read(groupRepositoryProvider)
        .updateRole(
          groupId: group.groupId,
          roleId: role.roleId,
          name: role.name,
          color: role.color,
          permissions: permissions,
        );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final liveGroup =
        ref.watch(watchedGroupProvider(group.groupId)).value ?? group;
    final colorScheme = Theme.of(context).colorScheme;
    final canEdit = hasGroupPermission(
      group: liveGroup,
      userId: currentUserId,
      permission: GroupPermission.managePermissions,
    );

    return StreamBuilder<List<GroupRole>>(
      stream: ref.watch(groupRepositoryProvider).watchRoles(group.groupId),
      builder: (context, snapshot) {
        final allRoles = snapshot.data ?? const <GroupRole>[];
        final everyone = allRoles.firstWhereOrNull((r) => r.isEveryone);
        final regular = allRoles.where((r) => !r.isEveryone).toList();
        final fallbackIndex = regular.length;
        regular.sort((a, b) {
          final indexA = liveGroup.rolePriority.indexOf(a.roleId);
          final indexB = liveGroup.rolePriority.indexOf(b.roleId);
          return (indexA == -1 ? fallbackIndex : indexA).compareTo(
            indexB == -1 ? fallbackIndex : indexB,
          );
        });

        // ロールの数に合わせてポップアップの幅を広げ、画面幅（ダイアログの
        // 左右余白を除く）を超える分はロール列の横スクロールに任せる。
        final needed =
            _kLabelWidth +
            _kFixedColumnWidth * 2 +
            regular.length * _kRoleColumnWidth;
        final available = MediaQuery.sizeOf(context).width - _kDialogInset;
        final width = needed
            .clamp(_kMinWidth, available < _kMinWidth ? _kMinWidth : available)
            .toDouble();

        return SizedBox(
          width: width,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 4, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        strings.groupMenuManagePermissions,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  strings.groupPermissionMatrixHint,
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: Builder(
                  builder: (context) {
                    Widget cell(Widget child, {Color? background}) => Container(
                      height: _kRowHeight,
                      alignment: Alignment.center,
                      color: background,
                      child: child,
                    );
                    Widget headerCell(
                      Widget child, {
                      required double width,
                      Color? background,
                    }) => Container(
                      width: width,
                      height: _kHeaderHeight,
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      color: background,
                      child: child,
                    );
                    Widget roleCheckbox(GroupRole role, String permission) =>
                        Checkbox(
                          value: role.permissions.contains(permission),
                          onChanged: canEdit
                              ? (checked) => _toggle(
                                  ref,
                                  role,
                                  permission,
                                  checked ?? false,
                                )
                              : null,
                        );

                    final everyoneBackground = colorScheme.onSurface.withValues(
                      alpha: 0.06,
                    );

                    final fixedPart = Column(
                      children: [
                        Row(
                          children: [
                            const SizedBox(
                              width: _kLabelWidth,
                              height: _kHeaderHeight,
                            ),
                            headerCell(
                              Text(
                                strings.groupPermissionColumnOwner,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              width: _kFixedColumnWidth,
                            ),
                            headerCell(
                              Text(
                                strings.groupPermissionColumnEveryone,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              width: _kFixedColumnWidth,
                              background: everyoneBackground,
                            ),
                          ],
                        ),
                        for (final permission in GroupPermission.all)
                          Row(
                            children: [
                              SizedBox(
                                width: _kLabelWidth,
                                child: Padding(
                                  padding: const EdgeInsets.only(
                                    left: 16,
                                    right: 8,
                                  ),
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: SizedBox(
                                      height: _kRowHeight,
                                      child: Align(
                                        alignment: Alignment.centerLeft,
                                        child: Text(
                                          strings.groupPermissionLabel(
                                            permission,
                                          ),
                                          style: const TextStyle(fontSize: 13),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: _kFixedColumnWidth,
                                child: cell(
                                  const Checkbox(value: true, onChanged: null),
                                ),
                              ),
                              SizedBox(
                                width: _kFixedColumnWidth,
                                child: cell(
                                  everyone == null
                                      ? const SizedBox.shrink()
                                      : roleCheckbox(everyone, permission),
                                  background: everyoneBackground,
                                ),
                              ),
                            ],
                          ),
                      ],
                    );

                    final rolePart = Column(
                      children: [
                        Row(
                          children: [
                            for (final role in regular)
                              headerCell(
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (role.color != null) ...[
                                      CircleAvatar(
                                        radius: 5,
                                        backgroundColor: Color(
                                          0xFF000000 | role.color!,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                    ],
                                    Flexible(
                                      child: Text(
                                        role.name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                width: _kRoleColumnWidth,
                              ),
                          ],
                        ),
                        for (final permission in GroupPermission.all)
                          Row(
                            children: [
                              for (final role in regular)
                                SizedBox(
                                  width: _kRoleColumnWidth,
                                  child: cell(roleCheckbox(role, permission)),
                                ),
                            ],
                          ),
                      ],
                    );

                    return SingleChildScrollView(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          fixedPart,
                          Expanded(child: _HorizontalScroll(child: rolePart)),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// ロール列の横スクロール。幅が足りない時にスクロールできると分かるよう、
/// 常にスクロールバーを表示する。
class _HorizontalScroll extends StatefulWidget {
  const _HorizontalScroll({required this.child});

  final Widget child;

  @override
  State<_HorizontalScroll> createState() => _HorizontalScrollState();
}

class _HorizontalScrollState extends State<_HorizontalScroll> {
  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      controller: _controller,
      thumbVisibility: true,
      notificationPredicate: (n) => n.metrics.axis == Axis.horizontal,
      child: SingleChildScrollView(
        controller: _controller,
        scrollDirection: Axis.horizontal,
        child: widget.child,
      ),
    );
  }
}
