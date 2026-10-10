import 'package:cloud_firestore/cloud_firestore.dart';

/// 受信Webhook（寄合へ外部から投稿できる、bot・API段階1、2026-10-10追加）の
/// 1件分（`groups/{groupId}/webhooks/{webhookId}`）。トークンのハッシュは
/// クライアントには持たせない（一覧に必要な項目だけ読む）。URLは作成時に
/// 1回しか返らないため、ここには含まれない。
class Webhook {
  const Webhook({
    required this.webhookId,
    required this.name,
    required this.roomId,
    this.createdAt,
    this.lastUsedAt,
  });

  final String webhookId;

  /// BOT名として投稿に表示される名前。
  final String name;

  /// 投稿先の寄合。
  final String roomId;
  final Timestamp? createdAt;
  final Timestamp? lastUsedAt;

  factory Webhook.fromJson(String webhookId, Map<String, dynamic> json) {
    return Webhook(
      webhookId: webhookId,
      name: json['name'] as String? ?? '',
      roomId: json['roomId'] as String? ?? '',
      createdAt: json['createdAt'] as Timestamp?,
      lastUsedAt: json['lastUsedAt'] as Timestamp?,
    );
  }
}

/// `createWebhook`の結果。[url]はこの応答でしか得られない（再表示不可）。
class CreatedWebhook {
  const CreatedWebhook({required this.webhookId, required this.url});

  final String webhookId;
  final String url;
}
