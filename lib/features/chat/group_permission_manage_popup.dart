import 'package:collection/collection.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';
import '../../models/group.dart';
import '../../models/group_role.dart';
import '../../providers/app_ui_style_provider.dart';
import '../../providers/group_providers.dart';
import '../../providers/repository_providers.dart';
import '../../utils/group_permissions.dart';
import '../../utils/platform_info.dart';
import '../../widgets/style_choice_chip.dart';

/// ポップアップの幅（ダイアログの左右余白を除いた画面幅に収まるよう制限する）。
const _kMaxWidth = 420.0;

/// コンピューター版（左ロール・右権限の2ペイン）の幅と、左ペインの幅・高さ。
const _kWideMaxWidth = 720.0;
const _kRolePaneWidth = 200.0;
const _kWidePaneHeight = 440.0;

/// 2ペイン表示に必要な、ダイアログ内で使える最小幅。
const _kWideMinAvailable = 560.0;
const _kDialogInset = 80.0;

/// 「長」を表す選択肢の固定キー（ロールidとは衝突しない）。
const _kOwnerKey = '__owner__';

/// 広場の権限をロールごとに確認・編集するダイアログ（2026-10-10追加、
/// 2026-10-11に「権限×ロール」の表から「ロール選択＋チェックボックス一覧」へ変更）。
/// 表はロール数に応じて横幅が増えモバイルで収まらなかったため、上部でロールを
/// 選ぶと、そのロールの各権限が縦のチェックボックス一覧に切り替わる形にした。
/// 全メンバーに最初から付く基準ロール（[GroupRole.isEveryone]）が何を許可して
/// いるかも「全員」を選べば分かる。チェックの切り替えは即時に保存する
/// （`GroupPermission.managePermissions`を持つメンバーのみ編集できる）。
class GroupPermissionManagePopup extends ConsumerStatefulWidget {
  const GroupPermissionManagePopup({
    required this.group,
    required this.currentUserId,
    super.key,
  });

  final Group group;

  /// 操作しているメンバー。`managePermissions`を持つ場合だけ編集できる
  /// （持たなければ閲覧のみ、2026-10-11）。
  final String currentUserId;

  @override
  ConsumerState<GroupPermissionManagePopup> createState() =>
      _GroupPermissionManagePopupState();
}

class _GroupPermissionManagePopupState
    extends ConsumerState<GroupPermissionManagePopup> {
  /// 選択中のロールid。null（または一覧から消えたロール）は「全員」。
  String? _selectedKey;

  Future<void> _toggle(GroupRole role, String permission, bool allowed) {
    final permissions = {...role.permissions};
    if (allowed) {
      permissions.add(permission);
    } else {
      permissions.remove(permission);
    }
    return ref
        .read(groupRepositoryProvider)
        .updateRole(
          groupId: widget.group.groupId,
          roleId: role.roleId,
          name: role.name,
          color: role.color,
          permissions: permissions,
        );
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final liveGroup =
        ref.watch(watchedGroupProvider(widget.group.groupId)).value ??
        widget.group;
    final colorScheme = Theme.of(context).colorScheme;
    final canEdit = hasGroupPermission(
      group: liveGroup,
      userId: widget.currentUserId,
      permission: GroupPermission.managePermissions,
    );

    return StreamBuilder<List<GroupRole>>(
      stream: ref
          .watch(groupRepositoryProvider)
          .watchRoles(widget.group.groupId),
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

        // 選択中のロールが消えた場合は「全員」（基準ロールがまだ無ければ長）へ戻す。
        final selectable = <String>{
          _kOwnerKey,
          ?everyone?.roleId,
          ...regular.map((r) => r.roleId),
        };
        final selectedKey = selectable.contains(_selectedKey)
            ? _selectedKey!
            : (everyone?.roleId ?? _kOwnerKey);
        final selectedRole = selectedKey == _kOwnerKey
            ? null
            : allRoles.firstWhereOrNull((r) => r.roleId == selectedKey);

        final available = MediaQuery.sizeOf(context).width - _kDialogInset;
        // コンピューター判定でも、ウィンドウが狭くて2ペインが窮屈になる幅
        // （スマホ相当の幅のブラウザ等）では従来のチップ＋縦リストにする。
        final isComputer =
            classifyDevice(context) == DeviceClass.computer &&
            available >= _kWideMinAvailable;
        final maxWidth = isComputer ? _kWideMaxWidth : _kMaxWidth;
        final width = available < maxWidth ? available : maxWidth;

        final uiStyle = ref.watch(appUiStyleProvider);
        final entries = <({String key, Widget Function(Color) label})>[
          (
            key: _kOwnerKey,
            label: (fg) => Text(
              strings.groupPermissionColumnOwner,
              style: TextStyle(color: fg),
            ),
          ),
          if (everyone != null)
            (
              key: everyone.roleId,
              label: (fg) => Text(
                strings.groupPermissionColumnEveryone,
                style: TextStyle(color: fg),
              ),
            ),
          for (final role in regular)
            (
              key: role.roleId,
              label: (fg) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (role.color != null) ...[
                    CircleAvatar(
                      radius: 5,
                      backgroundColor: Color(0xFF000000 | role.color!),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Flexible(
                    child: Text(
                      role.name,
                      style: TextStyle(color: fg),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
        ];
        Widget roleChip(
          ({String key, Widget Function(Color) label}) entry, {
          bool expand = false,
        }) => StyleChoiceChip(
          uiStyle: uiStyle,
          selected: selectedKey == entry.key,
          onTap: () => setState(() => _selectedKey = entry.key),
          labelBuilder: entry.label,
          expand: expand,
        );

        final permissionTiles = [
          for (final permission in GroupPermission.all)
            CheckboxListTile(
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(strings.groupPermissionLabel(permission)),
              // 長は常に全権限（変更不可）。
              value: selectedRole == null
                  ? true
                  : selectedRole.permissions.contains(permission),
              onChanged: canEdit && selectedRole != null
                  ? (checked) =>
                        _toggle(selectedRole, permission, checked ?? false)
                  : null,
            ),
        ];

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
                  isComputer
                      ? strings.groupPermissionMatrixHintWide
                      : strings.groupPermissionMatrixHint,
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (isComputer) ...[
                const Divider(height: 1),
                SizedBox(
                  height: _kWidePaneHeight,
                  child: Row(
                    children: [
                      SizedBox(
                        width: _kRolePaneWidth,
                        child: ListView(
                          padding: const EdgeInsets.all(12),
                          children: [
                            for (final entry in entries)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: roleChip(entry, expand: true),
                              ),
                          ],
                        ),
                      ),
                      const VerticalDivider(width: 1),
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          children: permissionTiles,
                        ),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                // 既定ではマウスのドラッグでスクロールできないため、PCでも
                // スワイプ同様に掴んで動かせるようマウスを許可する。
                ScrollConfiguration(
                  behavior: ScrollConfiguration.of(context).copyWith(
                    // デスクトップでは自動でスクロールバーが付くため明示的に消す。
                    scrollbars: false,
                    dragDevices: {
                      ...ScrollConfiguration.of(context).dragDevices,
                      PointerDeviceKind.mouse,
                    },
                  ),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Row(
                      children: [
                        for (final entry in entries)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: roleChip(entry),
                          ),
                      ],
                    ),
                  ),
                ),
                const Divider(height: 1),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(children: permissionTiles),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
