import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../models/bot.dart';

/// AIエージェント連携（bot API、2026-11-09）。トークンの作成・再発行・削除は
/// ハッシュを扱うためCloud Functions経由。一覧の購読だけFirestoreを直接読む
/// （firestore.rulesで所有者のみ）。
abstract class BotRepository {
  Stream<List<Bot>> watchMyBots(String userId);

  /// AIエージェント連携のトークンを作る。トークンは**この1回しか取得出来ない**。
  Future<BotToken> createBot(String name);

  Future<String> rotateToken(String botId);

  Future<void> deleteBot(String botId);
}

class FirestoreBotRepository implements BotRepository {
  FirestoreBotRepository({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _functions =
           functions ??
           FirebaseFunctions.instanceFor(region: 'asia-northeast1');

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;

  @override
  Stream<List<Bot>> watchMyBots(String userId) {
    return _firestore
        .collection('bots')
        .where('ownerUserId', isEqualTo: userId)
        .snapshots()
        .map((snapshot) {
          final bots = [
            for (final doc in snapshot.docs) Bot.fromJson(doc.id, doc.data()),
          ];
          bots.sort(
            (a, b) => (a.createdAt?.millisecondsSinceEpoch ?? 0).compareTo(
              b.createdAt?.millisecondsSinceEpoch ?? 0,
            ),
          );
          return bots;
        });
  }

  Future<Map<String, dynamic>> _call(
    String name,
    Map<String, Object?> data,
  ) async {
    final result = await _functions.httpsCallable(name).call(data);
    return Map<String, dynamic>.from(result.data as Map);
  }

  @override
  Future<BotToken> createBot(String name) async {
    final data = await _call('createBot', {'name': name});
    return BotToken(
      botId: data['botId'] as String,
      token: data['token'] as String,
    );
  }

  @override
  Future<String> rotateToken(String botId) async {
    final data = await _call('rotateBotToken', {'botId': botId});
    return data['token'] as String;
  }

  @override
  Future<void> deleteBot(String botId) async {
    await _call('deleteBot', {'botId': botId});
  }
}
