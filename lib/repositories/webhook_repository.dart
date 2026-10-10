import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../models/webhook.dart';

/// 受信Webhook（寄合へ外部から投稿できる、bot・API段階1、2026-10-10追加）。
/// 作成・削除はトークンのハッシュを扱うためCloud Functions
/// （`createWebhook`/`deleteWebhook`）経由で、権限（`manageBots`）の確認も
/// 関数側で行う。一覧の購読だけFirestoreを直接読む（firestore.rulesで
/// `manageBots`権限者のみ許可）。
abstract class WebhookRepository {
  Stream<List<Webhook>> watchWebhooks(String groupId);

  /// Webhookを作成し、トークン入りのURLを返す（**この1回しか取得できない**）。
  Future<CreatedWebhook> createWebhook({
    required String groupId,
    required String roomId,
    required String name,
  });

  Future<void> deleteWebhook({
    required String groupId,
    required String webhookId,
  });
}

class FirestoreWebhookRepository implements WebhookRepository {
  FirestoreWebhookRepository({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _functions =
           functions ??
           FirebaseFunctions.instanceFor(region: 'asia-northeast1');

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;

  @override
  Stream<List<Webhook>> watchWebhooks(String groupId) {
    return _firestore
        .collection('groups')
        .doc(groupId)
        .collection('webhooks')
        .orderBy('createdAt')
        .snapshots()
        .map(
          (snapshot) => [
            for (final doc in snapshot.docs)
              Webhook.fromJson(doc.id, doc.data()),
          ],
        );
  }

  @override
  Future<CreatedWebhook> createWebhook({
    required String groupId,
    required String roomId,
    required String name,
  }) async {
    final result = await _functions.httpsCallable('createWebhook').call({
      'groupId': groupId,
      'roomId': roomId,
      'name': name,
    });
    final data = Map<String, dynamic>.from(result.data as Map);
    return CreatedWebhook(
      webhookId: data['webhookId'] as String,
      url: data['url'] as String,
    );
  }

  @override
  Future<void> deleteWebhook({
    required String groupId,
    required String webhookId,
  }) async {
    await _functions.httpsCallable('deleteWebhook').call({
      'groupId': groupId,
      'webhookId': webhookId,
    });
  }
}
