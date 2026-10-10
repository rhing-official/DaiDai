import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:daidai/features/admin/admin_user_list.dart';
import 'package:daidai/models/app_ui_style.dart';
import 'package:daidai/models/app_user.dart';
import 'package:daidai/models/profile_card.dart';
import 'package:daidai/models/profile_material.dart';
import 'package:daidai/widgets/sns_link_list.dart';
import 'package:daidai/providers/app_ui_style_provider.dart';
import 'package:daidai/providers/repository_providers.dart';
import 'package:daidai/repositories/user_repository.dart';
import 'package:daidai/widgets/generated_avatar.dart';
import 'package:daidai/widgets/profile_card_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 管理画面の一覧が呼ぶ2メソッドだけを記録するリポジトリ。それ以外は呼ばれない
/// 想定（呼ばれたら`noSuchMethod`で失敗する）。
class _RecordingUserRepository implements UserRepository {
  final suspendCalls = <({List<String> ids, bool suspend})>[];
  final profileViewCalls = <({String userId, String reason, String note})>[];

  @override
  Future<BulkSuspendResult> setAccountsSuspended(
    List<String> userIds,
    bool suspended,
  ) async {
    suspendCalls.add((ids: userIds, suspend: suspended));
    return BulkSuspendResult(changed: userIds, skipped: const []);
  }

  /// trueなら`logAdminProfileView`が失敗する（関数が未デプロイ等の再現）。
  bool failProfileView = false;

  @override
  Future<void> logAdminProfileView(
    String userId, {
    required String reason,
    String note = '',
  }) async {
    if (failProfileView) throw Exception('not-found');
    profileViewCalls.add((userId: userId, reason: reason, note: note));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

AppUser _user(
  String id, {
  AccountStatus status = AccountStatus.active,
  DateTime? created,
}) => AppUser(
  userId: id,
  rhingSeed: id,
  accountStatus: status,
  createdAt: created == null ? null : Timestamp.fromDate(created),
);

void main() {
  test('生成アバターの色は同じIDなら常に同じで、パレットの中から選ばれる', () {
    expect(GeneratedAvatar.colorFor('abc'), GeneratedAvatar.colorFor('abc'));
    expect(GeneratedAvatar.palette, contains(GeneratedAvatar.colorFor('abc')));
    final colors = {
      for (var i = 0; i < 30; i++) GeneratedAvatar.colorFor('user$i'),
    };
    expect(colors.length, greaterThan(1));
  });

  group('filterAdminUsers', () {
    final users = [
      _user('alice', created: DateTime(2026, 1, 1)),
      _user(
        'bob',
        status: AccountStatus.suspended,
        created: DateTime(2026, 3, 1),
      ),
      _user('carol', status: AccountStatus.pendingDeletion),
      _user('Alicia', created: DateTime(2026, 2, 1)),
    ];

    test('@rhingSeedの部分一致（先頭の@・大文字小文字は無視）', () {
      final ids = filterAdminUsers(users, query: '@ALI').map((u) => u.userId);
      expect(ids, ['Alicia', 'alice']);
    });

    test('状態で絞り込む', () {
      expect(
        filterAdminUsers(
          users,
          filter: AdminUserFilter.suspended,
        ).single.userId,
        'bob',
      );
      expect(
        filterAdminUsers(
          users,
          filter: AdminUserFilter.pendingDeletion,
        ).single.userId,
        'carol',
      );
    });

    test('作成日で並べ替え、日時が無い人は常に末尾', () {
      expect(filterAdminUsers(users).map((u) => u.userId), [
        'bob',
        'Alicia',
        'alice',
        'carol',
      ]);
      expect(
        filterAdminUsers(
          users,
          sort: AdminUserSort.createdAsc,
        ).map((u) => u.userId),
        ['alice', 'Alicia', 'bob', 'carol'],
      );
    });
  });

  group('一覧の操作', () {
    late _RecordingUserRepository repo;

    Future<void> pump(WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      repo = _RecordingUserRepository();
      tester.view.physicalSize = const Size(1000, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final users = [
        _user('me'),
        AppUser(
          userId: 'alice',
          rhingSeed: 'alice',
          snsLinks: const [SnsLink(id: 's1', url: 'https://note.com/alice')],
          profileCards: const [
            ProfileCard(id: 'c1', name: '標準', snsLinkIds: ['s1']),
          ],
          activeProfileCardId: 'c1',
        ),
        _user('bob'),
        _user('gone', status: AccountStatus.pendingDeletion),
      ];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            initialAppUiStyleProvider.overrideWithValue(AppUiStyle.flat),
            userRepositoryProvider.overrideWithValue(repo),
            allUsersForAdminProvider.overrideWith((ref) => Stream.value(users)),
          ],
          child: const MaterialApp(
            home: Scaffold(body: AdminUserListSection(currentUserId: 'me')),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('自分・削除申請中の行にはチェックボックスが出ない', (tester) async {
      await pump(tester);
      // 全選択（1つ）＋選べる住人（alice・bob）の2つ。
      expect(find.byType(Checkbox), findsNWidgets(3));
    });

    testWidgets('複数選択して確認し、一括停止を実行する', (tester) async {
      await pump(tester);
      await tester.tap(find.byType(Checkbox).at(1));
      await tester.tap(find.byType(Checkbox).at(2));
      await tester.pump();
      expect(find.text('2件選択中'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, '停止'));
      await tester.pumpAndSettle();
      expect(find.text('2件のアカウントを停止しますか？'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, '停止する'));
      await tester.pumpAndSettle();

      expect(repo.suspendCalls, hasLength(1));
      expect(repo.suspendCalls.single.suspend, isTrue);
      expect(repo.suspendCalls.single.ids.toSet(), {'alice', 'bob'});
    });

    testWidgets('プロフィールは理由を選んで記録するまで表示されない', (tester) async {
      await pump(tester);
      await tester.tap(find.text('@alice'));
      await tester.pumpAndSettle();
      expect(find.byType(ProfileCardView), findsNothing);

      await tester.tap(find.text('プロフィールを確認'));
      await tester.pumpAndSettle();
      // 理由が未選択の間は実行できない。
      final record = find.widgetWithText(FilledButton, '記録して表示');
      expect(tester.widget<FilledButton>(record).onPressed, isNull);

      await tester.tap(find.text('通報への対応'));
      await tester.pump();
      await tester.tap(record);
      await tester.pumpAndSettle();

      expect(repo.profileViewCalls, hasLength(1));
      expect(repo.profileViewCalls.single.userId, 'alice');
      expect(repo.profileViewCalls.single.reason, 'report');
      expect(find.byType(ProfileCardView), findsOneWidget);
      // 住人側と同じ基準サイズで描く（縮小は外側のFittedBoxが担う）。
      final card = tester.widget<ProfileCardView>(find.byType(ProfileCardView));
      expect(card.width, 480);
      expect(card.height, 600);
      // SNSのURLは住人が作ったカードと同じくカードの中に出し、外には出さない。
      expect(card.snsLinks.map((l) => l.url), ['https://note.com/alice']);
      expect(find.byType(SnsLinkList), findsNothing);
    });

    testWidgets('記録に失敗したらカードは出さず、エラーがダイアログに残る', (tester) async {
      await pump(tester);
      repo.failProfileView = true;
      await tester.tap(find.text('@alice'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('プロフィールを確認'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('通報への対応'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, '記録して表示'));
      await tester.pumpAndSettle();

      expect(find.byType(ProfileCardView), findsNothing);
      // 数秒たっても消えない（バナーではなくダイアログ内に残る）。
      await tester.pump(const Duration(seconds: 10));
      expect(find.textContaining('記録に失敗したため表示できません'), findsOneWidget);
    });
  });
}
