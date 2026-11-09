import 'package:cloud_firestore/cloud_firestore.dart';

/// 住人が持つAIエージェント連携（bot API、2026-11-09）の1件（`bots/{botId}`）。
/// 自分のAIが、自分の参加している全ての広場・一対を読み、返信するためのトークン。
/// トークンのハッシュはクライアントには持たせない。トークンは作成・再発行時の応答でしか
/// 得られない。
class Bot {
  const Bot({
    required this.botId,
    required this.name,
    this.createdAt,
    this.lastUsedAt,
  });

  final String botId;
  final String name;
  final Timestamp? createdAt;
  final Timestamp? lastUsedAt;

  factory Bot.fromJson(String botId, Map<String, dynamic> json) {
    return Bot(
      botId: botId,
      name: json['name'] as String? ?? '',
      createdAt: json['createdAt'] as Timestamp?,
      lastUsedAt: json['lastUsedAt'] as Timestamp?,
    );
  }
}

/// `createBot`・`rotateBotToken`の結果。[token]はこの応答でしか得られない。
class BotToken {
  const BotToken({required this.botId, required this.token});

  final String botId;
  final String token;
}
