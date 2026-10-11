import 'package:daidai/models/group_invite_preview.dart';
import 'package:daidai/models/group_join_request.dart';
import 'package:flutter_test/flutter_test.dart';

// 招待URLから参加画面を開くと「null is not a subtype of String」で止まる不具合
// （2026-10-11）の回帰テスト。古い・欠けたドキュメントでも例外にならず読めること。
void main() {
  group('GroupJoinRequest.fromJson', () {
    test('改名前の旧フィールド名（requesterRhingId）のみのドキュメントも読める', () {
      final request = GroupJoinRequest.fromJson('u1', {
        'groupId': 'g1',
        'requesterId': 'u1',
        'requesterRhingId': 'taro',
        'status': 'pending',
      });
      expect(request.requesterRhingSeed, 'taro');
      expect(request.status, GroupJoinRequestStatus.pending);
    });

    test('必須のはずのフィールドが欠けていても例外にならない', () {
      final request = GroupJoinRequest.fromJson('u1', {});
      expect(request.requesterRhingSeed, '');
      expect(request.requesterId, 'u1');
      expect(request.status, GroupJoinRequestStatus.pending);
    });

    test('新フィールド名はそのまま読める', () {
      final request = GroupJoinRequest.fromJson('u1', {
        'groupId': 'g1',
        'requesterId': 'u1',
        'requesterRhingSeed': 'hanako',
        'status': 'declined',
      });
      expect(request.requesterRhingSeed, 'hanako');
      expect(request.status, GroupJoinRequestStatus.declined);
    });
  });

  test('GroupInvitePreview.fromJson: nameが無い古いプレビューでも読める', () {
    final preview = GroupInvitePreview.fromJson({'description': 'd'});
    expect(preview.name, '');
    expect(preview.description, 'd');
  });
}
