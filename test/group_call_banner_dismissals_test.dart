import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daidai/providers/group_call_banner_dismissals.dart';

void main() {
  group('shouldShowGroupCallBanner', () {
    test('進行中の通話があり、未参加・未閉鎖なら出す', () {
      expect(
        shouldShowGroupCallBanner(
          activeGroupCallId: 'c1',
          joinedGroupCallId: null,
          liveParticipantCount: 1,
          dismissedIds: const {},
        ),
        isTrue,
      );
    });

    test('参加者の読み込み中（掛けた直後）は出さない', () {
      expect(
        shouldShowGroupCallBanner(
          activeGroupCallId: 'c1',
          joinedGroupCallId: null,
          dismissedIds: const {},
          liveParticipantCount: null,
        ),
        isFalse,
      );
    });

    test('通話に入っている人が0人なら出さない、1人以上なら出す', () {
      expect(
        shouldShowGroupCallBanner(
          activeGroupCallId: 'c1',
          joinedGroupCallId: null,
          dismissedIds: const {},
          liveParticipantCount: 0,
        ),
        isFalse,
      );
      expect(
        shouldShowGroupCallBanner(
          activeGroupCallId: 'c1',
          joinedGroupCallId: null,
          dismissedIds: const {},
          liveParticipantCount: 1,
        ),
        isTrue,
      );
    });

    test('通話が無い・自分が参加済み・閉じたら出さない', () {
      expect(
        shouldShowGroupCallBanner(
          activeGroupCallId: null,
          joinedGroupCallId: null,
          liveParticipantCount: 1,
          dismissedIds: const {},
        ),
        isFalse,
      );
      expect(
        shouldShowGroupCallBanner(
          activeGroupCallId: 'c1',
          joinedGroupCallId: 'c1',
          liveParticipantCount: 1,
          dismissedIds: const {},
        ),
        isFalse,
      );
      expect(
        shouldShowGroupCallBanner(
          activeGroupCallId: 'c1',
          joinedGroupCallId: null,
          liveParticipantCount: 1,
          dismissedIds: const {'c1'},
        ),
        isFalse,
      );
    });

    test('別の通話に参加中、又は別の通話を閉じていても、この通話は出す', () {
      expect(
        shouldShowGroupCallBanner(
          activeGroupCallId: 'c2',
          joinedGroupCallId: 'c1',
          liveParticipantCount: 1,
          dismissedIds: const {'c1'},
        ),
        isTrue,
      );
    });
  });

  test('閉じた通話のidを、通話単位で覚える', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(groupCallBannerDismissalsProvider), isEmpty);
    container.read(groupCallBannerDismissalsProvider.notifier).dismiss('c1');
    container.read(groupCallBannerDismissalsProvider.notifier).dismiss('c2');
    expect(container.read(groupCallBannerDismissalsProvider), {'c1', 'c2'});
  });
}
