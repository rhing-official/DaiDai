import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:daidai/models/group.dart';
import 'package:daidai/providers/chat_room_message_cache.dart';
import 'package:daidai/utils/group_permissions.dart';
import 'package:flutter_test/flutter_test.dart';

Group _group({
  bool historyVisible = false,
  Map<String, Timestamp> joinedAt = const {},
}) {
  return Group(
    groupId: 'g1',
    name: 'g',
    ownerId: 'owner',
    memberIds: const ['owner', 'newbie'],
    memberRoles: const {'owner': 'owner', 'newbie': 'member'},
    historyVisibleToNewMembers: historyVisible,
    memberJoinedAt: joinedAt,
  );
}

Room _room({bool custom = false, bool? override}) {
  return Room(
    roomId: 'r1',
    groupId: 'g1',
    name: 'room',
    memberIds: const ['owner', 'newbie'],
    customSettingsEnabled: custom,
    historyVisibleOverride: override,
  );
}

void main() {
  final joined = Timestamp.fromMillisecondsSinceEpoch(1000000);

  test('Group.fromJson: 欠落時は履歴を見せない・加入時刻なし（既存の広場）', () {
    final group = Group.fromJson('g1', {
      'name': 'g',
      'ownerId': 'owner',
      'memberIds': ['owner'],
      'memberRoles': {'owner': 'owner'},
    });
    expect(group.historyVisibleToNewMembers, isFalse);
    expect(group.memberJoinedAt, isEmpty);
  });

  test('Group.fromJson: 加入時刻を読み込む', () {
    final group = Group.fromJson('g1', {
      'name': 'g',
      'ownerId': 'owner',
      'memberIds': ['owner', 'newbie'],
      'memberRoles': {'owner': 'owner', 'newbie': 'member'},
      'historyVisibleToNewMembers': true,
      'memberJoinedAt': {'newbie': joined},
    });
    expect(group.historyVisibleToNewMembers, isTrue);
    expect(group.memberJoinedAt['newbie'], joined);
  });

  group('effectiveHistoryVisible', () {
    test('寄合の独自設定がオフなら広場の既定に従う（上書きがあっても無視）', () {
      expect(
        effectiveHistoryVisible(
          group: _group(historyVisible: false),
          room: _room(custom: false, override: true),
        ),
        isFalse,
      );
    });

    test('独自設定がオンなら上書きが優先、nullなら広場の既定', () {
      expect(
        effectiveHistoryVisible(
          group: _group(historyVisible: false),
          room: _room(custom: true, override: true),
        ),
        isTrue,
      );
      expect(
        effectiveHistoryVisible(
          group: _group(historyVisible: true),
          room: _room(custom: true, override: false),
        ),
        isFalse,
      );
      expect(
        effectiveHistoryVisible(
          group: _group(historyVisible: true),
          room: _room(custom: true),
        ),
        isTrue,
      );
    });
  });

  group('messageVisibleFrom', () {
    test('加入時刻の記録が無いメンバー（既存メンバー・長）は制限なし', () {
      expect(
        messageVisibleFrom(group: _group(), room: null, userId: 'owner'),
        isNull,
      );
    });

    test('新規加入者は、履歴を見せない設定の間は加入時刻以降だけ', () {
      final group = _group(joinedAt: {'newbie': joined});
      expect(
        messageVisibleFrom(group: group, room: null, userId: 'newbie'),
        joined,
      );
    });

    test('履歴を見せる設定（広場の既定／寄合の上書き）なら制限なし', () {
      expect(
        messageVisibleFrom(
          group: _group(historyVisible: true, joinedAt: {'newbie': joined}),
          room: _room(),
          userId: 'newbie',
        ),
        isNull,
      );
      expect(
        messageVisibleFrom(
          group: _group(joinedAt: {'newbie': joined}),
          room: _room(custom: true, override: true),
          userId: 'newbie',
        ),
        isNull,
      );
    });

    test('寄合の上書きで見せない設定にすると、広場が見せる設定でも制限される', () {
      expect(
        messageVisibleFrom(
          group: _group(historyVisible: true, joinedAt: {'newbie': joined}),
          room: _room(custom: true, override: false),
          userId: 'newbie',
        ),
        joined,
      );
    });
  });

  test('ChatRoomCacheKey: 閲覧開始時刻が違えば別エントリになる', () {
    const base = ChatRoomCacheKey(
      isDm: false,
      conversationId: 'g1',
      roomId: 'r1',
    );
    const restricted = ChatRoomCacheKey(
      isDm: false,
      conversationId: 'g1',
      roomId: 'r1',
      visibleFromMicros: 1000,
    );
    expect(base, isNot(restricted));
    expect(
      restricted,
      const ChatRoomCacheKey(
        isDm: false,
        conversationId: 'g1',
        roomId: 'r1',
        visibleFromMicros: 1000,
      ),
    );
  });
}
