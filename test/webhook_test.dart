import 'package:daidai/features/chat/webhook_management_popup.dart';
import 'package:daidai/l10n/app_locale.dart';
import 'package:daidai/l10n/strings.dart';
import 'package:daidai/models/app_ui_style.dart';
import 'package:daidai/models/app_user.dart';
import 'package:daidai/models/group.dart';
import 'package:daidai/models/group_role.dart';
import 'package:daidai/models/message.dart';
import 'package:daidai/models/webhook.dart';
import 'package:daidai/providers/app_locale_provider.dart';
import 'package:daidai/providers/app_ui_style_provider.dart';
import 'package:daidai/providers/repository_providers.dart';
import 'package:daidai/repositories/group_repository.dart';
import 'package:daidai/repositories/webhook_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeWebhooks implements WebhookRepository {
  final created = <Map<String, String>>[];
  final deleted = <String>[];

  @override
  Stream<List<Webhook>> watchWebhooks(String groupId) => Stream.value([
    const Webhook(webhookId: 'w1', name: 'CI通知', roomId: 'r1'),
  ]);

  @override
  Future<CreatedWebhook> createWebhook({
    required String groupId,
    required String roomId,
    required String name,
  }) async {
    created.add({'roomId': roomId, 'name': name});
    return const CreatedWebhook(
      webhookId: 'w2',
      url: 'https://example.test/postWebhookMessage/g1/w2/SECRET',
    );
  }

  @override
  Future<void> deleteWebhook({
    required String groupId,
    required String webhookId,
  }) async {
    deleted.add(webhookId);
  }
}

class _FakeGroups implements GroupRepository {
  @override
  Stream<List<Room>> watchRooms({
    required String groupId,
    required String userId,
  }) => Stream.value([
    const Room(roomId: 'r1', groupId: 'g1', name: 'メイン', memberIds: ['u1']),
  ]);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('Message.botName', () {
    final json = {
      'conversationId': 'r1',
      'conversationType': 'room',
      'senderId': 'webhook:w1',
      'senderRhingSeed': null,
      'botName': 'CI通知',
      'content': 'ビルド成功',
      'contentType': 'text',
    };

    test('fromJson: botNameを読み込む（人間のメッセージではnull）', () {
      expect(Message.fromJson('m1', json).botName, 'CI通知');
      expect(
        Message.fromJson('m2', {...json}..remove('botName')).botName,
        isNull,
      );
    });

    test('toJson: クライアントからはbotNameを書かない（nullなら出力しない）', () {
      final human = Message(
        messageId: 'm',
        conversationId: 'r1',
        conversationType: 'room',
        senderId: 'u1',
        content: 'hi',
        contentType: 'text',
      );
      expect(human.toJson().containsKey('botName'), isFalse);
    });
  });

  test('GroupPermission.manageBots: 権限一覧に含まれ、日英のラベルがある', () {
    expect(GroupPermission.all, contains(GroupPermission.manageBots));
    expect(
      Strings.of(
        AppLocale.japanese,
      ).groupPermissionLabel(GroupPermission.manageBots),
      'botとWebhookの管理',
    );
    expect(
      Strings.of(
        AppLocale.britishEnglish,
      ).groupPermissionLabel(GroupPermission.manageBots),
      'Manage bots and webhooks',
    );
  });

  group('WebhookManagementPopup', () {
    late _FakeWebhooks webhooks;

    Future<void> pump(WidgetTester tester) async {
      webhooks = _FakeWebhooks();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            webhookRepositoryProvider.overrideWithValue(webhooks),
            groupRepositoryProvider.overrideWithValue(_FakeGroups()),
            initialAppLocaleProvider.overrideWithValue(AppLocale.japanese),
            initialAppUiStyleProvider.overrideWithValue(AppUiStyle.flat),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: WebhookManagementPopup(
                currentUser: AppUser(userId: 'u1', rhingSeed: 'seed'),
                group: const Group(
                  groupId: 'g1',
                  name: 'g',
                  ownerId: 'u1',
                  memberIds: ['u1'],
                  memberRoles: {'u1': 'owner'},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('一覧に名前と投稿先の寄合・未使用が出る', (tester) async {
      await pump(tester);
      expect(find.text('CI通知'), findsOneWidget);
      expect(find.textContaining('メイン'), findsOneWidget);
      expect(find.textContaining('未使用'), findsOneWidget);
    });

    testWidgets('作成するとURLを1回だけ表示し、閉じると再表示されない', (tester) async {
      await pump(tester);
      await tester.tap(find.text('Webhookを作成'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'デプロイ通知');
      await tester.pump();
      await tester.tap(find.text('作成'));
      await tester.pumpAndSettle();

      expect(webhooks.created, [
        {'roomId': 'r1', 'name': 'デプロイ通知'},
      ]);
      expect(find.textContaining('SECRET'), findsWidgets);
      expect(find.text('このURLは今しか表示されません。必ず今コピーして保管してください。'), findsOneWidget);

      await tester.tap(find.text('完了'));
      await tester.pumpAndSettle();
      expect(find.textContaining('SECRET'), findsNothing);
    });

    testWidgets('削除は確認ダイアログの後に実行される（キャンセルでは実行しない）', (tester) async {
      await pump(tester);
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      await tester.tap(find.text('キャンセル'));
      await tester.pumpAndSettle();
      expect(webhooks.deleted, isEmpty);

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      await tester.tap(find.text('削除する'));
      await tester.pumpAndSettle();
      expect(webhooks.deleted, ['w1']);
    });
  });
}
