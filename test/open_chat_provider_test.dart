import 'package:daidai/models/direct_message.dart';
import 'package:daidai/providers/talks_resume_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const dm = DirectMessage(
    dmId: 'a_b',
    participants: ['a', 'b'],
    participantRhingSeeds: {'a': 'a', 'b': 'b'},
  );
  OpenChat chat(String room) => OpenChat.dm(dm, roomId: room, roomName: room);

  test('古い所有者のcloseは、新しい所有者の記録を消さない（寄合の切り替えでStateが作り直される場合）', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(openChatProvider.notifier);
    final oldOwner = Object();
    final newOwner = Object();

    notifier.open(chat('r1'), owner: oldOwner);
    // 新しいStateが先に記録し、その後に古いStateのcloseが走る。
    notifier.open(chat('r2'), owner: newOwner);
    notifier.close(oldOwner);
    expect(container.read(openChatProvider)?.roomId, 'r2');

    notifier.close(newOwner);
    expect(container.read(openChatProvider), isNull);
  });

  test('同じ所有者の再記録は寄合の更新で、closeで消える', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(openChatProvider.notifier);
    final owner = Object();
    notifier.open(chat('r1'), owner: owner);
    notifier.open(chat('r2'), owner: owner);
    expect(container.read(openChatProvider)?.roomId, 'r2');
    notifier.close(owner);
    expect(container.read(openChatProvider), isNull);
  });
}
