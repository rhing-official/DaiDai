import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;

import '../../../models/app_user.dart';
import '../../../models/conversation_prefs.dart';
import '../../../models/direct_message.dart';
import '../../../models/dm_room.dart';
import '../../../models/friend.dart';
import '../../../models/friend_request.dart';
import '../../../models/group.dart';
import '../../../models/group_join_request.dart';
import '../../../models/message.dart';
import '../../../models/note.dart';
import '../../../repositories/album_repository.dart';
import '../../../repositories/block_repository.dart';
import '../../../repositories/calendar_category_repository.dart';
import '../../../repositories/calendar_event_repository.dart';
import '../../../repositories/call_repository.dart';
import '../../../repositories/group_call_repository.dart';
import '../../../repositories/note_repository.dart';
import '../../../repositories/poll_repository.dart';
import '../../../repositories/schedule_coordination_repository.dart';
import '../../../repositories/conversation_prefs_repository.dart';
import '../../../repositories/direct_message_repository.dart';
import '../../../repositories/friend_repository.dart';
import '../../../repositories/group_repository.dart';
import '../../../models/sticker.dart';
import '../../../models/sticker_role.dart';
import '../../../repositories/sticker_repository.dart';
import '../../../repositories/user_repository.dart';

// 使い方ガイドの練習用の画面（`PracticeHome`）が使う、メモリ上だけの偽のリポジトリ
// （2026-10-17追加）。本物のFirestoreには一切触れず、何も保存・送信しない。
// 本物の語らいタブ（`TalksTab`）・会話画面をそのまま動かし、ユーザーの設定
// （一覧の見た目・チャットのレイアウト等）に合った画面で解説するために使う。

/// 偽のリポジトリが実装していないメソッドが呼ばれた時の既定の振る舞い（何もしない）。
/// `watch…`は何も流れないストリーム、それ以外は完了済みのFuture（書き込み系の
/// 呼び出し＝下書きの保存・既読の記録などを、例外にせず黙って受け流す）。
/// 例外にすると、ユーザーの設定（下書きの同期など）によっては送信が失敗して見える。
dynamic _lenient(Invocation invocation) {
  final name = invocation.memberName.toString();
  if (name.contains('"watch')) return const Stream<Never>.empty();
  return Future<void>.value();
}

/// 練習用の自分・練習相手のid（実在のアカウントとは無関係）。
const practiceSelfId = 'practice-user';
const practiceFriendId = 'practice-friend';
const practiceDmIdPrefix = 'practice-dm-';
const practiceRoomId = 'practice-room';

/// 練習用の自分。
const practiceUser = AppUser(
  userId: practiceSelfId,
  rhingSeed: 'practice',
  displayName: 'Practice',
  // カレンダーを開く時のGoogleカレンダー連携の確認（と本物の認証）を出さない。
  googleCalendarSyncEnabled: false,
);

/// 練習相手（語らいの相手）。
const practiceFriend = AppUser(
  userId: practiceFriendId,
  rhingSeed: 'daidai',
  displayName: 'DaiDai',
);

/// 練習用の`UserRepository`。偽のユーザーを返すだけで、何も書き込まない。
class PracticeUserRepository implements UserRepository {
  @override
  Stream<AppUser?> watchUser(String userId) =>
      Stream.value(userId == practiceFriendId ? practiceFriend : practiceUser);

  @override
  Future<AppUser?> getUser(String userId) async =>
      userId == practiceFriendId ? practiceFriend : practiceUser;

  @override
  Future<List<AppUser>> getUsersByIds(List<String> userIds) async => [
    for (final id in userIds)
      if (id == practiceFriendId) practiceFriend else practiceUser,
  ];

  @override
  Future<void> syncInvitePreview(String userId) async {}

  @override
  Future<void> refreshInviteLink(String userId) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => _lenient(invocation);
}

/// 練習用の`DirectMessageRepository`。練習相手との一対1件だけを持つ。
/// メッセージは新しい順（先頭が最新）で持ち、送ると先頭へ追加する。
class PracticeDirectMessageRepository implements DirectMessageRepository {
  PracticeDirectMessageRepository({required this.greeting}) {
    _messages.add(
      Message(
        messageId: 'practice-greeting',
        conversationId: dmId,
        conversationType: 'dm',
        senderId: practiceFriendId,
        senderRhingSeed: practiceFriend.rhingSeed,
        content: greeting,
        contentType: 'text',
        sentAt: Timestamp.now(),
      ),
    );
  }

  final String greeting;

  /// この練習用の会話のid。会話のメッセージは、アプリ全体で共有される取得用の
  /// キャッシュ（`chatRoomMessageCacheManagerProvider`）にidをキーとして残るため、
  /// 練習のたびに違うidにする（前回の練習の購読を引き継いで、送ったメッセージが
  /// 表示されなくなるのを防ぐ）。
  final String dmId =
      '$practiceDmIdPrefix${DateTime.now().microsecondsSinceEpoch}';
  final _messages = <Message>[];
  final _messagesController = StreamController<List<Message>>.broadcast();
  final _dmController = StreamController<DirectMessage?>.broadcast();
  int _nextId = 1;

  /// 練習用の会話（初期設定のプレビューで、会話を開いた状態にするため公開）。
  DirectMessage get directMessage => _dm;

  DirectMessage get _dm {
    final last = _messages.first;
    return DirectMessage(
      dmId: dmId,
      participants: const [practiceSelfId, practiceFriendId],
      participantRhingSeeds: {
        practiceSelfId: practiceUser.rhingSeed,
        practiceFriendId: practiceFriend.rhingSeed,
      },
      lastMessageAt: last.sentAt,
      lastMessageSenderId: last.senderId,
      lastMessageContentType: last.contentType,
      lastMessagePreview: last.content,
    );
  }

  DmRoom get _room => DmRoom(
    roomId: practiceRoomId,
    dmId: dmId,
    name: 'main',
    participants: const [practiceSelfId, practiceFriendId],
  );

  Stream<T> _replaying<T>(
    StreamController<T> controller,
    T Function() current,
  ) => Stream<T>.multi((subscriber) {
    subscriber.add(current());
    final sub = controller.stream.listen(subscriber.add);
    subscriber.onCancel = sub.cancel;
  }, isBroadcast: true);

  @override
  Stream<List<DirectMessage>> watchDirectMessages(String userId) =>
      _replaying(_dmController, () => _dm).map((dm) => [if (dm != null) dm]);

  @override
  Stream<DirectMessage?> watchDirectMessage(String dmId) =>
      _replaying(_dmController, () => _dm);

  @override
  Future<DirectMessage?> getDirectMessage(String dmId) async => _dm;

  @override
  Stream<List<DmRoom>> watchRooms({
    required String dmId,
    required String userId,
  }) => Stream.value([_room]);

  @override
  Stream<List<Message>> watchMessages(String dmId, String roomId) =>
      _replaying(_messagesController, () => List.unmodifiable(_messages));

  @override
  Future<List<Message>> loadOlderMessages({
    required String dmId,
    required String roomId,
    required dynamic before,
    int limit = 30,
  }) async => const [];

  @override
  Future<void> sendTextMessage({
    required String dmId,
    required String roomId,
    required String senderId,
    required String senderRhingSeed,
    required String content,
    bool silent = false,
    Message? replyTo,
    MessageMentions mentions = MessageMentions.none,
  }) async {
    _messages.insert(
      0,
      Message(
        messageId: 'practice-${_nextId++}',
        conversationId: dmId,
        conversationType: 'dm',
        senderId: senderId,
        senderRhingSeed: senderRhingSeed,
        content: content,
        contentType: 'text',
        sentAt: Timestamp.now(),
      ),
    );
    _messagesController.add(List.unmodifiable(_messages));
    _dmController.add(_dm);
  }

  @override
  Future<List<Message>> getRecentMessagesForSearch({
    required String dmId,
    required String roomId,
    int limit = 200,
  }) async => List.unmodifiable(_messages);

  @override
  Future<List<Message>> getMessagesAround({
    required String dmId,
    required String roomId,
    required String messageId,
    int contextSize = 25,
  }) async => List.unmodifiable(_messages);

  @override
  Future<Message?> getMessage({
    required String dmId,
    required String roomId,
    required String messageId,
  }) async {
    for (final message in _messages) {
      if (message.messageId == messageId) return message;
    }
    return null;
  }

  @override
  Future<void> markMessagesRead({
    required String dmId,
    required String roomId,
    required String userId,
    required List<String> messageIds,
  }) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => _lenient(invocation);
}

/// 練習用の`GroupRepository`。広場は1件も無い。
class PracticeGroupRepository implements GroupRepository {
  @override
  Stream<List<Group>> watchGroups(String userId) => Stream.value(const []);

  @override
  Stream<List<GroupJoinRequest>> watchMyJoinRequests(String userId) =>
      Stream.value(const []);

  @override
  dynamic noSuchMethod(Invocation invocation) => _lenient(invocation);
}

/// 練習用の`FriendRepository`。申請も友達も無い。
class PracticeFriendRepository implements FriendRepository {
  @override
  Stream<List<FriendRequest>> watchIncomingRequests(String userId) =>
      Stream.value(const []);

  @override
  Stream<List<FriendRequest>> watchOutgoingRequests(String userId) =>
      Stream.value(const []);

  @override
  Stream<List<Friend>> watchFriends(String userId) => Stream.value(const []);

  @override
  dynamic noSuchMethod(Invocation invocation) => _lenient(invocation);
}

/// 練習用の`BlockRepository`。ブロックは無い。
class PracticeBlockRepository implements BlockRepository {
  @override
  Stream<Set<String>> watchBlockedUserIds(String userId) =>
      Stream.value(const <String>{});

  @override
  dynamic noSuchMethod(Invocation invocation) => _lenient(invocation);
}

/// 練習用の`ConversationPrefsRepository`。ピン留め・通知オフは無い。
class PracticeConversationPrefsRepository
    implements ConversationPrefsRepository {
  @override
  Stream<Map<String, ConversationPrefs>> watchAll(String userId) =>
      Stream.value(const <String, ConversationPrefs>{});

  @override
  dynamic noSuchMethod(Invocation invocation) => _lenient(invocation);
}

/// 練習用の`StickerRepository`。ぺったんのパックは1つも無い。
class PracticeStickerRepository implements StickerRepository {
  @override
  Stream<List<StickerPack>> watchPacks() => Stream.value(const []);

  @override
  Stream<List<StickerPack>> watchOwnedPacks(String userId) =>
      Stream.value(const []);

  @override
  Stream<List<StickerRole>> watchRoles() => Stream.value(const []);

  @override
  Future<String?> findPackIdForSticker(String stickerId) async => null;

  @override
  Future<bool> ownsPack(String userId, String packId) async => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => _lenient(invocation);
}

/// 会話の周りの機能（カレンダー・ノート・アルバム・投票・通話など）の偽のリポジトリ
/// に共通の「何もしない」振る舞い。`watch…`は何も流れない（読み込み中のまま）ストリーム、
/// それ以外は完了しないFutureを返す。練習用の画面ではこれらの機能を使わないため、
/// 本物のFirestoreへ触れないことだけを保証する。
mixin InertRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    final name = invocation.memberName.toString();
    if (name.contains('"watch')) return const Stream<Never>.empty();
    return Completer<Never>().future;
  }
}

/// 会話の周りの機能のうち、練習用の画面で**開いて見せる**もの（アルバム・ノート・
/// カレンダー・予定調整・投票）の偽のリポジトリに共通の「空のデータ」を返す振る舞い。
/// 一覧は空、単体は`null`、取得は空/`null`。画面が読み込み中のままにならず、
/// 「まだありません」の空の状態で開く。書き込みは何もしない。
mixin EmptyRepository {
  static const _single = {'watchNote', 'watchSyncState', 'watchPoll'};
  static const _singleGet = {
    'getNote',
    'getEvent',
    'getSyncState',
    'getCoordination',
    'getPoll',
  };

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final name = invocation.memberName.toString().replaceAll(
      RegExp(r'Symbol\("|"\)'),
      '',
    );
    if (name.startsWith('watch')) {
      return _single.contains(name)
          ? Stream<Null>.value(null)
          : Stream.value(const <Never>[]);
    }
    if (_singleGet.contains(name)) return Future<Null>.value(null);
    if (name == 'participantIds') return Future.value(const <Never>[]);
    return Future<void>.value();
  }
}

class PracticeAlbumRepository with EmptyRepository implements AlbumRepository {}

class PracticeCalendarEventRepository
    with EmptyRepository
    implements CalendarEventRepository {}

class PracticeCalendarCategoryRepository
    with EmptyRepository
    implements CalendarCategoryRepository {}

class PracticeScheduleCoordinationRepository
    with EmptyRepository
    implements ScheduleCoordinationRepository {}

class PracticePollRepository with EmptyRepository implements PollRepository {}

/// 練習用のノート。一覧にも本体にもこの1件だけが入る。中身は空で、ガイドの中で
/// 実際に書いて覚える。保存・同期は何もしない。
class PracticeNoteRepository with EmptyRepository implements NoteRepository {
  PracticeNoteRepository({required this.title});

  final String title;

  Note get _note => Note(
    noteId: 'practice-note',
    roomId: 'practice-room',
    title: title,
    content: const {},
    createdBy: 'practice-friend',
    updatedAt: Timestamp.now(),
  );

  @override
  Stream<List<Note>> watchNotes({
    required bool isDm,
    required String conversationId,
    required String roomId,
  }) => Stream.value([_note]);

  @override
  Future<Note?> getNote({
    required bool isDm,
    required String conversationId,
    required String roomId,
    required String noteId,
  }) async => _note;
}

class PracticeCallRepository with InertRepository implements CallRepository {}

class PracticeGroupCallRepository
    with InertRepository
    implements GroupCallRepository {}
