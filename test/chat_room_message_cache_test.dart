import 'dart:async';

import 'package:daidai/models/day_messages_page.dart';
import 'package:daidai/models/message.dart';
import 'package:daidai/providers/chat_room_message_cache.dart';
import 'package:flutter_test/flutter_test.dart';

Message _message(String id) => Message(
  messageId: id,
  conversationId: 'conv',
  conversationType: 'room',
  senderId: 'sender',
  content: id,
  contentType: 'text',
);

void main() {
  const key = ChatRoomCacheKey(
    isDm: true,
    conversationId: 'dm-1',
    roomId: 'room-1',
  );

  test('ensureSubscribedで購読した値がliveTailMessagesへ反映される', () async {
    final entry = ChatRoomMessageCacheEntry();
    final controller = StreamController<DayMessagesPage>();
    entry.ensureSubscribed(() => controller.stream);

    final dayStart = DateTime(2026, 9, 10);
    controller.add(
      DayMessagesPage(dayStart: dayStart, messages: [_message('a')]),
    );
    await pumpEventQueue();

    expect(entry.liveTailMessages.map((m) => m.messageId), ['a']);
    expect(entry.oldestLoadedDayStart, dayStart);

    await controller.close();
  });

  test('同じキーでattachし直しても既存データを引き継ぎ、購読を張り直さない', () async {
    final manager = ChatRoomMessageCacheManager();
    var subscribeCount = 0;
    final controller = StreamController<DayMessagesPage>();
    Stream<DayMessagesPage> watch() {
      subscribeCount++;
      return controller.stream;
    }

    final first = manager.attach(key);
    first.ensureSubscribed(watch);
    controller.add(
      DayMessagesPage(
        dayStart: DateTime(2026, 9, 10),
        messages: [_message('a')],
      ),
    );
    await pumpEventQueue();
    manager.detach(key, first);

    final second = manager.attach(key);
    second.ensureSubscribed(watch); // 既に購読済みなら何もしないはず

    expect(identical(first, second), isTrue);
    expect(subscribeCount, 1);
    expect(second.liveTailMessages.map((m) => m.messageId), ['a']);

    await controller.close();
  });

  test('detachしてもrefCountが0になるだけで購読はキャンセルされない', () {
    final manager = ChatRoomMessageCacheManager();
    var cancelled = false;
    final controller = StreamController<DayMessagesPage>(
      onCancel: () => cancelled = true,
    );
    addTearDown(controller.close);

    final entry = manager.attach(key);
    entry.ensureSubscribed(() => controller.stream);
    manager.detach(key, entry);

    // maxIdleEntries未満なので破棄されず、再attachで同一インスタンスが返る。
    final reattached = manager.attach(key);
    expect(identical(entry, reattached), isTrue);
    expect(cancelled, isFalse);
  });

  test('maxIdleEntriesを超えたら最も古くdetachされたものから購読が破棄される', () {
    final manager = ChatRoomMessageCacheManager();
    final controllers = <StreamController<DayMessagesPage>>[];
    addTearDown(() {
      for (final c in controllers) {
        c.close();
      }
    });

    final keys = List.generate(
      ChatRoomMessageCacheManager.maxIdleEntries + 2,
      (i) => ChatRoomCacheKey(
        isDm: true,
        conversationId: 'dm-1',
        roomId: 'room-$i',
      ),
    );
    final entries = <ChatRoomCacheKey, ChatRoomMessageCacheEntry>{};
    for (final k in keys) {
      final controller = StreamController<DayMessagesPage>();
      controllers.add(controller);
      final entry = manager.attach(k);
      entry.ensureSubscribed(() => controller.stream);
      entries[k] = entry;
      // detachする順序をkeysの順にする（古い順にidleSinceが進む）。
      manager.detach(k, entry);
    }

    // 最初にdetachされた2件（maxIdleEntriesを超えた分）は破棄され、
    // 再attachすると新規インスタンスになる。
    final reattachedFirst = manager.attach(keys.first);
    expect(identical(reattachedFirst, entries[keys.first]), isFalse);

    // 直近detachされたものは生き残っているはず。
    final reattachedLast = manager.attach(keys.last);
    expect(identical(reattachedLast, entries[keys.last]), isTrue);
  });

  test('表示中(refCount>0)のエントリはmaxIdleEntriesを超えても破棄されない', () {
    final manager = ChatRoomMessageCacheManager();
    final controllers = <StreamController<DayMessagesPage>>[];
    addTearDown(() {
      for (final c in controllers) {
        c.close();
      }
    });

    final displayedKey = const ChatRoomCacheKey(
      isDm: true,
      conversationId: 'dm-1',
      roomId: 'displayed',
    );
    final displayedController = StreamController<DayMessagesPage>();
    controllers.add(displayedController);
    final displayedEntry = manager.attach(displayedKey);
    displayedEntry.ensureSubscribed(() => displayedController.stream);
    // detachしない＝表示中のまま。

    for (var i = 0; i < ChatRoomMessageCacheManager.maxIdleEntries + 5; i++) {
      final k = ChatRoomCacheKey(
        isDm: true,
        conversationId: 'dm-1',
        roomId: 'idle-$i',
      );
      final controller = StreamController<DayMessagesPage>();
      controllers.add(controller);
      final entry = manager.attach(k);
      entry.ensureSubscribed(() => controller.stream);
      manager.detach(k, entry);
    }

    final reattachedDisplayed = manager.attach(displayedKey);
    expect(identical(reattachedDisplayed, displayedEntry), isTrue);
  });

  test('loadOlderはページが無くなるとhasMoreHistoryをfalseにする', () async {
    final entry = ChatRoomMessageCacheEntry();
    final controller = StreamController<DayMessagesPage>();
    addTearDown(controller.close);
    entry.ensureSubscribed(() => controller.stream);
    final dayStart = DateTime(2026, 9, 10);
    controller.add(DayMessagesPage(dayStart: dayStart, messages: const []));
    await pumpEventQueue();

    await entry.loadOlder((before) async => null);

    expect(entry.hasMoreHistory, isFalse);
  });

  test('loadOlderは取得したページをolderMessagesへ追記し境界を更新する', () async {
    final entry = ChatRoomMessageCacheEntry();
    final controller = StreamController<DayMessagesPage>();
    addTearDown(controller.close);
    entry.ensureSubscribed(() => controller.stream);
    final dayStart = DateTime(2026, 9, 10);
    controller.add(DayMessagesPage(dayStart: dayStart, messages: const []));
    await pumpEventQueue();

    final olderDayStart = DateTime(2026, 9, 9);
    await entry.loadOlder((before) async {
      expect(before, dayStart);
      return DayMessagesPage(
        dayStart: olderDayStart,
        messages: [_message('old')],
      );
    });

    expect(entry.olderMessages.map((m) => m.messageId), ['old']);
    expect(entry.oldestLoadedDayStart, olderDayStart);
    expect(entry.hasMoreHistory, isTrue);
  });

  test(
    'afterMutationはliveTailMessages側のIDを無視し、olderMessages側のみ差し替える',
    () async {
      final entry = ChatRoomMessageCacheEntry();
      final controller = StreamController<DayMessagesPage>();
      addTearDown(controller.close);
      entry.ensureSubscribed(() => controller.stream);
      controller.add(
        DayMessagesPage(
          dayStart: DateTime(2026, 9, 10),
          messages: [_message('live-1')],
        ),
      );
      await pumpEventQueue();
      entry.olderMessages.add(_message('older-1'));

      var actionCalled = false;
      await entry.afterMutation(
        () async {
          actionCalled = true;
        },
        messageIds: ['live-1', 'older-1'],
        fetchMessage: (id) async {
          expect(id, 'older-1'); // liveTailMessages側は再取得されない
          return _message('older-1-edited');
        },
      );

      expect(actionCalled, isTrue);
      expect(entry.olderMessages.single.content, 'older-1-edited');
    },
  );

  test('afterMutationは再取得結果がnullなら該当メッセージを削除する', () async {
    final entry = ChatRoomMessageCacheEntry();
    entry.olderMessages.add(_message('older-1'));

    await entry.afterMutation(
      () async {},
      messageIds: ['older-1'],
      fetchMessage: (id) async => null,
    );

    expect(entry.olderMessages, isEmpty);
  });

  test('evictConversationは同じ会話に属する全寄合の購読を破棄する', () {
    final manager = ChatRoomMessageCacheManager();
    final controllerA = StreamController<DayMessagesPage>();
    final controllerB = StreamController<DayMessagesPage>();
    addTearDown(() {
      controllerA.close();
      controllerB.close();
    });
    const keyA = ChatRoomCacheKey(
      isDm: false,
      conversationId: 'group-1',
      roomId: 'a',
    );
    const keyB = ChatRoomCacheKey(
      isDm: false,
      conversationId: 'group-1',
      roomId: 'b',
    );
    final entryA = manager.attach(keyA)
      ..ensureSubscribed(() => controllerA.stream);
    final entryB = manager.attach(keyB)
      ..ensureSubscribed(() => controllerB.stream);
    manager.detach(keyA, entryA);
    manager.detach(keyB, entryB);

    manager.evictConversation('group-1');

    final reattachedA = manager.attach(keyA);
    expect(identical(reattachedA, entryA), isFalse);
  });
}
