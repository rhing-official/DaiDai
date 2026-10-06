import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:daidai/models/message_cursor.dart';

import 'package:daidai/models/message.dart';
import 'package:daidai/providers/chat_room_message_cache.dart';
import 'package:flutter_test/flutter_test.dart';

Message _message(String id, {int? seconds}) => Message(
  messageId: id,
  sentAt: seconds == null ? null : Timestamp(seconds, 0),
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
    final controller = StreamController<List<Message>>();
    entry.ensureSubscribed(() => controller.stream);

    controller.add([_message('a', seconds: 100)]);
    await pumpEventQueue();

    expect(entry.liveTailMessages.map((m) => m.messageId), ['a']);
    expect(entry.oldestLoadedCursor?.messageId, 'a');

    await controller.close();
  });

  test('同じキーでattachし直しても既存データを引き継ぎ、購読を張り直さない', () async {
    final manager = ChatRoomMessageCacheManager();
    var subscribeCount = 0;
    final controller = StreamController<List<Message>>();
    Stream<List<Message>> watch() {
      subscribeCount++;
      return controller.stream;
    }

    final first = manager.attach(key);
    first.ensureSubscribed(watch);
    controller.add([_message('a')]);
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
    final controller = StreamController<List<Message>>(
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
    final controllers = <StreamController<List<Message>>>[];
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
      final controller = StreamController<List<Message>>();
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
    final controllers = <StreamController<List<Message>>>[];
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
    final displayedController = StreamController<List<Message>>();
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
      final controller = StreamController<List<Message>>();
      controllers.add(controller);
      final entry = manager.attach(k);
      entry.ensureSubscribed(() => controller.stream);
      manager.detach(k, entry);
    }

    final reattachedDisplayed = manager.attach(displayedKey);
    expect(identical(reattachedDisplayed, displayedEntry), isTrue);
  });

  test('loadOlderは50件未満のページを受け取るとhasMoreHistoryをfalseにする', () async {
    final entry = ChatRoomMessageCacheEntry();
    final controller = StreamController<List<Message>>();
    addTearDown(controller.close);
    entry.ensureSubscribed(() => controller.stream);
    controller.add([_message('a', seconds: 100)]);
    await pumpEventQueue();

    await entry.loadOlder((before) async => const []);

    expect(entry.hasMoreHistory, isFalse);
  });

  test('loadOlderは空の寄合（ライブ窓が空）ならhasMoreHistoryをfalseにする', () async {
    final entry = ChatRoomMessageCacheEntry();
    final controller = StreamController<List<Message>>();
    addTearDown(controller.close);
    entry.ensureSubscribed(() => controller.stream);
    controller.add(const []);
    await pumpEventQueue();

    await entry.loadOlder((before) async => fail('呼ばれないはず'));

    expect(entry.hasMoreHistory, isFalse);
  });

  test('loadOlderは最古のメッセージをカーソルに渡し、ページ分を追記して継続する', () async {
    final entry = ChatRoomMessageCacheEntry();
    final controller = StreamController<List<Message>>();
    addTearDown(controller.close);
    entry.ensureSubscribed(() => controller.stream);
    controller.add([_message('b', seconds: 200), _message('a', seconds: 100)]);
    await pumpEventQueue();

    late MessageCursor received;
    await entry.loadOlder((before) async {
      received = before;
      return [
        for (var i = 0; i < kMessagePageSize; i++)
          _message('old-$i', seconds: 99 - i),
      ];
    });

    expect(received, MessageCursor(sentAt: Timestamp(100, 0), messageId: 'a'));
    expect(entry.olderMessages, hasLength(kMessagePageSize));
    expect(entry.oldestLoadedCursor?.messageId, 'old-${kMessagePageSize - 1}');
    expect(entry.hasMoreHistory, isTrue);
  });

  List<Message> fullWindow(int newestSeconds) => [
    for (var i = 0; i < kMessagePageSize; i++)
      _message('m${newestSeconds - i}', seconds: newestSeconds - i),
  ];

  test('ライブ窓が新着で進むと、押し出された分はolderMessagesの先頭へ移る', () async {
    final entry = ChatRoomMessageCacheEntry();
    final controller = StreamController<List<Message>>();
    addTearDown(controller.close);
    entry.ensureSubscribed(() => controller.stream);
    controller.add(fullWindow(1000)); // 1000..951
    await pumpEventQueue();
    controller.add(fullWindow(1001)); // 1001..952（951が押し出される）
    await pumpEventQueue();

    expect(entry.liveTailMessages.first.messageId, 'm1001');
    expect(entry.olderMessages.map((m) => m.messageId), ['m951']);
  });

  test('窓内で物理削除されたメッセージは、押し出し扱いにせず捨てる', () async {
    final entry = ChatRoomMessageCacheEntry();
    final controller = StreamController<List<Message>>();
    addTearDown(controller.close);
    entry.ensureSubscribed(() => controller.stream);
    final first = fullWindow(1000); // 1000..951
    controller.add(first);
    await pumpEventQueue();
    // m990が削除され、窓の下端に950が繰り上がる（件数は50のまま）
    final second = [
      for (final m in first)
        if (m.messageId != 'm990') m,
      _message('m950', seconds: 950),
    ];
    controller.add(second);
    await pumpEventQueue();

    expect(entry.olderMessages, isEmpty);
    expect(entry.liveTailMessages.any((m) => m.messageId == 'm990'), isFalse);
  });

  test('olderMessagesにいたメッセージが窓へ繰り上がったら重複しないよう除く', () async {
    final entry = ChatRoomMessageCacheEntry();
    final controller = StreamController<List<Message>>();
    addTearDown(controller.close);
    entry.ensureSubscribed(() => controller.stream);
    final first = fullWindow(1000); // 1000..951
    controller.add(first);
    await pumpEventQueue();
    entry.olderMessages.add(_message('m950', seconds: 950));
    final second = [
      for (final m in first)
        if (m.messageId != 'm990') m,
      _message('m950', seconds: 950),
    ];
    controller.add(second);
    await pumpEventQueue();

    expect(entry.olderMessages.where((m) => m.messageId == 'm950'), isEmpty);
    expect(entry.liveTailMessages.last.messageId, 'm950');
  });

  test('直前の窓と全く重ならない更新（古いキャッシュ→最新）はolderMessagesを捨てて読み直す', () async {
    final entry = ChatRoomMessageCacheEntry();
    final controller = StreamController<List<Message>>();
    addTearDown(controller.close);
    entry.ensureSubscribed(() => controller.stream);
    controller.add([_message('stale', seconds: 10)]);
    await pumpEventQueue();
    entry.olderMessages.add(_message('stale-old', seconds: 5));
    await entry.loadOlder((before) async => const []); // hasMoreHistory=false
    expect(entry.hasMoreHistory, isFalse);

    controller.add(fullWindow(1000));
    await pumpEventQueue();

    expect(entry.olderMessages, isEmpty);
    expect(entry.hasMoreHistory, isTrue);
    expect(entry.oldestLoadedCursor?.messageId, 'm951');
  });

  test(
    'afterMutationはliveTailMessages側のIDを無視し、olderMessages側のみ差し替える',
    () async {
      final entry = ChatRoomMessageCacheEntry();
      final controller = StreamController<List<Message>>();
      addTearDown(controller.close);
      entry.ensureSubscribed(() => controller.stream);
      controller.add([_message('live-1')]);
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
    final controllerA = StreamController<List<Message>>();
    final controllerB = StreamController<List<Message>>();
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
