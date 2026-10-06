import 'dart:async';

import 'package:daidai/models/message.dart';
import 'package:daidai/providers/chat_room_message_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  List<Message> page() => const [];

  test('終了した購読は、再度ensureSubscribedで再購読される', () async {
    final entry = ChatRoomMessageCacheEntry();
    var subscribed = 0;
    Stream<List<Message>> factory() {
      subscribed++;
      return Stream.value(page());
    }

    entry.ensureSubscribed(factory);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(subscribed, 1);
    entry.ensureSubscribed(factory);
    expect(subscribed, 2);
    entry.cancelSubscription();
  });

  test('エラーで止まった購読も、再度ensureSubscribedで再購読される', () async {
    final entry = ChatRoomMessageCacheEntry();
    var subscribed = 0;
    Stream<List<Message>> factory() {
      subscribed++;
      return Stream<List<Message>>.error(StateError('unavailable'));
    }

    entry.ensureSubscribed(factory);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    entry.ensureSubscribed(factory);
    expect(subscribed, 2);
    entry.cancelSubscription();
  });

  test('生きている購読は二重に張らない', () {
    final entry = ChatRoomMessageCacheEntry();
    final controller = StreamController<List<Message>>();
    var subscribed = 0;
    Stream<List<Message>> factory() {
      subscribed++;
      return controller.stream;
    }

    entry.ensureSubscribed(factory);
    entry.ensureSubscribed(factory);
    expect(subscribed, 1);
    entry.cancelSubscription();
    controller.close();
  });
}
