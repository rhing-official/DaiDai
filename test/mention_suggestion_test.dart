import 'package:daidai/models/app_user.dart';
import 'package:daidai/models/group.dart';
import 'package:daidai/models/group_role.dart';
import 'package:daidai/utils/group_mentions.dart';
import 'package:daidai/utils/mention_suggestion.dart';
import 'package:flutter_test/flutter_test.dart';

MentionCandidate user(String id, String label, [String? seed]) =>
    MentionCandidate(
      kind: MentionKind.user,
      id: id,
      label: label,
      subtitle: seed ?? label,
    );

void main() {
  group('detectMentionQuery', () {
    test('半角@の直後のクエリを検出する', () {
      final q = detectMentionQuery('こんにちは @ab', 9);
      expect(q?.query, 'ab');
      expect(q?.start, 6);
    });

    test('行頭の@、@のみ（空クエリ）も検出する', () {
      expect(detectMentionQuery('@', 1)?.query, '');
      expect(detectMentionQuery('a\n@x', 4)?.start, 2);
    });

    test('全角＠は対象外', () {
      expect(detectMentionQuery('＠ab', 3), isNull);
    });

    test('メールアドレスのようなa@bは対象外', () {
      expect(detectMentionQuery('a@b', 3), isNull);
    });

    test('空白を打つとメンション入力は終わる', () {
      expect(detectMentionQuery('@ab ', 4), isNull);
    });

    test('カーソルが@クエリの途中なら、カーソルまでをクエリとする', () {
      expect(detectMentionQuery('@abc', 3)?.query, 'ab');
    });
  });

  group('filterMentionCandidates', () {
    final all = [
      user('1', '新', 'arata'),
      user('2', 'しゃちょう', 'kaina'),
      user('3', '田中', 'tanaka'),
    ];

    test('空クエリは全件', () {
      expect(filterMentionCandidates(all, ''), all);
    });

    test('カタカナ・ひらがなの表記ゆれを吸収する', () {
      final r = filterMentionCandidates(all, 'シャチョウ');
      expect(r.map((c) => c.id), ['2']);
    });

    test('Rhing Seedにも一致し、前方一致が先に並ぶ', () {
      final r = filterMentionCandidates(all, 'a');
      expect(r.map((c) => c.id), ['1', '2', '3']);
      expect(filterMentionCandidates(all, 'tan').single.id, '3');
    });
  });

  test('mentionsStillInText: 本文から消した宛先は外し、重複は1件にする', () {
    final a = user('1', '新');
    final b = user('2', '社長');
    final r = mentionsStillInText('@新 おはよう @新', [a, b, a]);
    expect(r.map((c) => c.id), ['1']);
  });

  group('buildGroupMentionCandidates', () {
    AppUser appUser(String id, String seed) =>
        AppUser.fromJson({'userId': id, 'rhingSeed': seed});

    Group group({List<String> perms = const []}) => Group.fromJson('g1', {
      'ownerId': 'owner',
      'memberIds': ['owner', 'me', 'x'],
      'name': 'g',
      'memberRoles': <String, dynamic>{},
      'memberPermissions': {'me': perms},
    });

    final roles = [
      GroupRole(
        roleId: 'r1',
        groupId: 'g1',
        name: 'A tier',
        color: 0xFFC107,
        permissions: const {},
        isEveryone: false,
      ),
      GroupRole(
        roleId: 'base',
        groupId: 'g1',
        name: '全員',
        color: null,
        permissions: const {},
        isEveryone: true,
      ),
    ];
    final members = [
      appUser('owner', 'o'),
      appUser('me', 'm'),
      appUser('x', 'x'),
    ];

    test('権限が無ければメンバー（自分以外）のみ', () {
      final c = buildGroupMentionCandidates(
        group: group(),
        currentUserId: 'me',
        members: members,
        roles: roles,
      );
      expect(c.map((e) => e.kind).toSet(), {MentionKind.user});
      expect(c.map((e) => e.id), ['owner', 'x']);
    });

    test('mentionEveryone権限があれば@everyoneとロール（基準ロール除く）も出る', () {
      final c = buildGroupMentionCandidates(
        group: group(perms: [GroupPermission.mentionEveryone]),
        currentUserId: 'me',
        members: members,
        roles: roles,
      );
      expect(c.where((e) => e.kind == MentionKind.everyone), hasLength(1));
      expect(c.where((e) => e.kind == MentionKind.role).map((e) => e.id), [
        'r1',
      ]);
    });

    test('長は権限が無くても使える', () {
      final c = buildGroupMentionCandidates(
        group: group(),
        currentUserId: 'owner',
        members: members,
        roles: roles,
      );
      expect(c.any((e) => e.kind == MentionKind.everyone), isTrue);
    });
  });
}
