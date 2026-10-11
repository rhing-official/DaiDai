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
    String userId = 'u1',
    Group group = _group,
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
          watchedGroupProvider.overrideWith((ref, id) => Stream.value(group)),
          initialAppLocaleProvider.overrideWithValue(AppLocale.japanese),
          initialAppUiStyleProvider.overrideWithValue(AppUiStyle.flat),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: GroupPermissionManagePopup(
                group: group,
                currentUserId: userId,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  // 2026-10-11に「権限×ロールの表」から「ロールを選ぶチップ＋選んだロールの
  // 権限チェックボックス一覧」へ画面を変えたため、それに合わせたテスト。
  // テスト環境の端末はAndroid扱いのため、チップ＋縦リスト表示（最大幅420）になる。
  List<Checkbox> boxes(WidgetTester tester) =>
      tester.widgetList<Checkbox>(find.byType(Checkbox)).toList();

  testWidgets('ロールのチップ（長・全員・各ロール）と、全権限のチェックボックスが出る', (tester) async {
    await pump(tester);

    expect(find.text('権限管理'), findsOneWidget);
    expect(find.text('長'), findsOneWidget);
    expect(find.text('全員'), findsOneWidget);
    expect(find.text('運営係'), findsOneWidget);
    expect(find.text('招待リンクの作成'), findsOneWidget);
    // 選択中のロール1つ分（全権限7件）だけが縦に並ぶ。
    expect(find.byType(Checkbox), findsNWidgets(7));
    expect(tester.getSize(find.byType(GroupPermissionManagePopup)).width, 420);
  });

  testWidgets('最初は「全員」（基準ロール）が選ばれ、招待リンクの作成だけ許可', (tester) async {
    await pump(tester);

    final checked = boxes(tester).where((c) => c.value == true).length;
    expect(checked, 1);
  });

  testWidgets('ロールのチップを選ぶと、そのロールの権限に切り替わる', (tester) async {
    await pump(tester);

    await tester.tap(find.text('運営係'));
    await tester.pumpAndSettle();
    // 運営係はmanageRoomsだけ許可（権限の並びの先頭）。
    final list = boxes(tester);
    expect(list.where((c) => c.value == true).length, 1);
    expect(list.first.value, isTrue);

    await tester.tap(find.text('長'));
    await tester.pumpAndSettle();
    // 長は常に全権限で、変更できない。
    final owner = boxes(tester);
    expect(owner.every((c) => c.value == true), isTrue);
    expect(owner.every((c) => c.onChanged == null), isTrue);
  });

  testWidgets('チェックを切り替えると、そのロールの権限集合でupdateRoleが呼ばれる', (tester) async {
    await pump(tester);

    // 「全員」の先頭の権限（manageRooms）をオンにする。
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();

    expect(groups.updates, hasLength(1));
    expect(groups.updates.single.roleId, 'everyone');
    expect(groups.updates.single.permissions, {
      GroupPermission.createInvite,
      GroupPermission.manageRooms,
    });
  });

  testWidgets('ロールが増えても幅は一定で、チップの列だけ横にスクロールできる', (tester) async {
    await pump(tester, extraRoles: 8, screenWidth: 500);
    expect(tester.getSize(find.byType(GroupPermissionManagePopup)).width, 420);

    final lastChip = find.text('ロール7');
    final before = tester.getTopLeft(lastChip).dx;
    final label = tester.getTopLeft(find.text('招待リンクの作成')).dx;

    await tester.drag(
      find.byType(SingleChildScrollView).first,
      const Offset(-300, 0),
    );
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(lastChip).dx, lessThan(before));
    // 下の権限の一覧は動かない。
    expect(tester.getTopLeft(find.text('招待リンクの作成')).dx, label);
  });

  testWidgets('権限の管理を持たないメンバーには閲覧のみで、タップしても保存されない', (tester) async {
    // 長ではなく、メンバーとしても権限の管理を持たない。
    const member = Group(
      groupId: 'g1',
      name: 'g',
      ownerId: 'u1',
      memberIds: ['u1', 'u2'],
      memberRoles: {'u1': 'owner'},
      memberPermissions: {
        'u2': [GroupPermission.manageRoles],
      },
    );
    await pump(tester, userId: 'u2', group: member);

    expect(boxes(tester).every((c) => c.onChanged == null), isTrue);
    await tester.tap(find.byType(Checkbox).first, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(groups.updates, isEmpty);
  });

  testWidgets('権限の管理を持つメンバーは、長でなくても編集できる', (tester) async {
    const member = Group(
      groupId: 'g1',
      name: 'g',
      ownerId: 'u1',
      memberIds: ['u1', 'u2'],
      memberRoles: {'u1': 'owner'},
      memberPermissions: {
        'u2': [GroupPermission.managePermissions],
      },
    );
    await pump(tester, userId: 'u2', group: member);

    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    expect(groups.updates, hasLength(1));
  });
}
