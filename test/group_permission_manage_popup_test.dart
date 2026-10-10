import 'package:daidai/features/chat/group_permission_manage_popup.dart';
import 'package:daidai/l10n/app_locale.dart';
import 'package:daidai/models/app_ui_style.dart';
import 'package:daidai/models/group.dart';
import 'package:daidai/models/group_role.dart';
import 'package:daidai/providers/app_locale_provider.dart';
import 'package:daidai/providers/app_ui_style_provider.dart';
import 'package:daidai/providers/group_providers.dart';
import 'package:daidai/providers/repository_providers.dart';
import 'package:daidai/repositories/group_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _group = Group(
  groupId: 'g1',
  name: 'g',
  ownerId: 'u1',
  memberIds: ['u1'],
  memberRoles: {'u1': 'owner'},
);

class _FakeGroups implements GroupRepository {
  _FakeGroups({this.extraRoles = 0});

  /// 「運営係」に加えて作る追加ロールの数（幅の確認用）。
  final int extraRoles;
  final updates = <({String roleId, Set<String> permissions})>[];

  @override
  Stream<List<GroupRole>> watchRoles(String groupId) => Stream.value([
    const GroupRole(
      roleId: 'everyone',
      groupId: 'g1',
      name: '全員',
      color: null,
      permissions: {GroupPermission.createInvite},
      isEveryone: true,
    ),
    const GroupRole(
      roleId: 'mod',
      groupId: 'g1',
      name: '運営係',
      color: 0xEE7800,
      permissions: {GroupPermission.manageRooms},
    ),
    for (var i = 0; i < extraRoles; i++)
      GroupRole(
        roleId: 'extra$i',
        groupId: 'g1',
        name: 'ロール$i',
        color: null,
        permissions: const {},
      ),
  ]);

  @override
  Future<void> updateRole({
    required String groupId,
    required String roleId,
    required String name,
    required int? color,
    required Set<String> permissions,
  }) async {
    updates.add((roleId: roleId, permissions: permissions));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _FakeGroups groups;

  Future<void> pump(
    WidgetTester tester, {
    int extraRoles = 0,
    double screenWidth = 900,
  }) async {
    groups = _FakeGroups(extraRoles: extraRoles);
    tester.view.physicalSize = Size(screenWidth, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          groupRepositoryProvider.overrideWithValue(groups),
          watchedGroupProvider.overrideWith((ref, id) => Stream.value(_group)),
          initialAppLocaleProvider.overrideWithValue(AppLocale.japanese),
          initialAppUiStyleProvider.overrideWithValue(AppUiStyle.flat),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: Center(child: GroupPermissionManagePopup(group: _group)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('権限×ロールの一覧に、全権限の行と長・全員・各ロールの列が出る', (tester) async {
    await pump(tester);

    expect(find.text('権限管理'), findsOneWidget);
    expect(find.text('長'), findsOneWidget);
    expect(find.text('全員'), findsOneWidget);
    expect(find.text('運営係'), findsOneWidget);
    expect(find.text('招待リンクの作成'), findsOneWidget);
    expect(find.byType(Checkbox), findsNWidgets(6 * 3));

    // 全員の列（基準ロール）は招待リンクの作成だけ許可。長は全て許可で固定。
    final checked = tester
        .widgetList<Checkbox>(find.byType(Checkbox))
        .where((c) => c.value == true)
        .length;
    expect(checked, 6 + 1 + 1); // 長6 + 全員1 + 運営係1
  });

  testWidgets('セルを切り替えると、そのロールの権限集合でupdateRoleが呼ばれる', (tester) async {
    await pump(tester);

    // 6行 × 3列の最初の「全員」列（行0=manageRooms）をオンにする。
    final checkboxes = find.byType(Checkbox);
    // 並びは固定部（長・全員を行ごと）→ロール部の順。全員列は2番目ごと。
    await tester.tap(checkboxes.at(1));
    await tester.pumpAndSettle();

    expect(groups.updates, hasLength(1));
    expect(groups.updates.single.roleId, 'everyone');
    expect(groups.updates.single.permissions, {
      GroupPermission.createInvite,
      GroupPermission.manageRooms,
    });
  });

  testWidgets('ロールが増えるとポップアップの幅が広がり、画面幅を超えない', (tester) async {
    await pump(tester);
    // 固定部334 + ロール1件96。
    expect(tester.getSize(find.byType(GroupPermissionManagePopup)).width, 430);

    await pump(tester, extraRoles: 3);
    expect(tester.getSize(find.byType(GroupPermissionManagePopup)).width, 718);

    // 画面幅900 - 余白80 = 820で頭打ち。
    await pump(tester, extraRoles: 10);
    expect(tester.getSize(find.byType(GroupPermissionManagePopup)).width, 820);
  });

  testWidgets('幅が足りない時は、ロール列だけ横にスクロールできる', (tester) async {
    await pump(tester, extraRoles: 8, screenWidth: 500);
    expect(tester.getSize(find.byType(GroupPermissionManagePopup)).width, 420);

    final lastHeader = find.text('ロール7');
    final before = tester.getTopLeft(lastHeader).dx;
    final label = tester.getTopLeft(find.text('招待リンクの作成')).dx;

    await tester.drag(
      find.byType(SingleChildScrollView).last,
      const Offset(-300, 0),
    );
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(lastHeader).dx, lessThan(before));
    // 左の固定部（権限名）は動かない。
    expect(tester.getTopLeft(find.text('招待リンクの作成')).dx, label);
  });
}
