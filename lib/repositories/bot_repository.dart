import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../models/bot.dart';

/// bot API（AIが寄合のメッセージを読み、返信できる、2026-11-09、段階2a）。
/// 作成・追加・承認はトークンのハッシュや権限確認を伴うためCloud Functions
/// 経由。一覧の購読だけFirestoreを直接読む（firestore.rulesで、自分のbotは
/// 所有者のみ、広場のbotは広場のメンバーのみ）。
abstract class BotRepository {
  Stream<List<Bot>> watchMyBots(String userId);

  Stream<List<GroupBot>> watchConversationBots(BotConversation conversation);

  /// botを作る。トークンは**この1回しか取得出来ない**。
  Future<BotToken> createBot(String name);

  Future<String> rotateToken(String botId);

  Future<void> deleteBot(String botId);

  /// 自分のbotを広場・一対へ追加する。承認なしで有効になった場合は
  /// [GroupBotStatus.active]、承認（一対は相手の同意）待ちなら
  /// [GroupBotStatus.pending]。
  Future<GroupBotStatus> requestAddition({
    required BotConversation conversation,
    required String botId,
  });

  Future<void> respond({
    required BotConversation conversation,
    required String botId,
    required bool approve,
  });

  Future<void> remove({
    required BotConversation conversation,
    required String botId,
  });
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

  @override
  Stream<List<GroupBot>> watchConversationBots(BotConversation conversation) {
    return _firestore
        .collection(conversation.isDm ? 'directMessages' : 'groups')
        .doc(conversation.id)
        .collection('bots')
        .snapshots()
        .map(
          (snapshot) => [
            for (final doc in snapshot.docs)
              GroupBot.fromJson(doc.id, doc.data()),
          ],
        );
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

  @override
  Future<GroupBotStatus> requestAddition({
    required BotConversation conversation,
    required String botId,
  }) async {
    final data = await _call('requestBotAddition', {
      ...conversation.toArgs(),
      'botId': botId,
    });
    return data['status'] == 'active'
        ? GroupBotStatus.active
        : GroupBotStatus.pending;
  }

  @override
  Future<void> respond({
    required BotConversation conversation,
    required String botId,
    required bool approve,
  }) async {
    await _call('respondBotAddition', {
      ...conversation.toArgs(),
      'botId': botId,
      'approve': approve,
    });
  }

  @override
  Future<void> remove({
    required BotConversation conversation,
    required String botId,
  }) async {
    await _call('removeBotFromGroup', {
      ...conversation.toArgs(),
      'botId': botId,
    });
  }
}
