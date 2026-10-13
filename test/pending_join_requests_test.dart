import 'package:cloud_firestore/cloud_firestore.dart' show FirebaseException;
import 'package:daidai/models/group.dart';
import 'package:daidai/models/group_join_request.dart';
import 'package:daidai/utils/pending_join_requests.dart';
import 'package:flutter_test/flutter_test.dart';

GroupJoinRequest _request(String groupId, [String id = 'u']) =>
    GroupJoinRequest(
      requestId: id,
      groupId: groupId,
      requesterId: 'u',
      requesterRhingSeed: 'u',
      status: GroupJoinRequestStatus.pending,
    );

Group _group(String id) => Group(
  groupId: id,
  name: id,
  ownerId: 'o',
  memberIds: const ['o', 'u'],
  memberRoles: const {},
);

void main() {
  test('既にメンバーの広場の承認待ちは出さない', () {
    final result = visiblePendingGroupRequests(
      [_request('g1'), _request('g2')],
      [_group('g1')],
    );
    expect(result.map((r) => r.groupId), ['g2']);
  });

  test('同じ広場の重複は1件にまとめる', () {
    final result = visiblePendingGroupRequests([
      _request('g1', 'a'),
      _request('g1', 'b'),
    ], const []);
    expect(result, hasLength(1));
  });

  test('空なら空', () {
    expect(visiblePendingGroupRequests(const [], [_group('g1')]), isEmpty);
  });

  test('却下された申請も出す（結果を伝え、本人が削除できるように）', () {
    const declined = GroupJoinRequest(
      requestId: 'u',
      groupId: 'g3',
      requesterId: 'u',
      requesterRhingSeed: 'u',
      status: GroupJoinRequestStatus.declined,
    );
    final result = visiblePendingGroupRequests([declined], const []);
    expect(result.single.status, GroupJoinRequestStatus.declined);
    // 後から承認されて既にメンバーなら、却下済みの古い申請も出さない。
    expect(visiblePendingGroupRequests([declined], [_group('g3')]), isEmpty);
  });

  group('joinRequestOutcome', () {
    GroupJoinRequest req(String groupId, GroupJoinRequestStatus status) =>
        GroupJoinRequest(
          requestId: 'u',
          groupId: groupId,
          requesterId: 'u',
          requesterRhingSeed: 'u',
          status: status,
        );

    test('読み込み前はloading（画面を閉じない）', () {
      expect(joinRequestOutcome(null, 'g1'), JoinRequestOutcome.loading);
    });

    test('承認待ち・却下はそのまま返す', () {
      expect(
        joinRequestOutcome([req('g1', GroupJoinRequestStatus.pending)], 'g1'),
        JoinRequestOutcome.pending,
      );
      expect(
        joinRequestOutcome([req('g1', GroupJoinRequestStatus.declined)], 'g1'),
        JoinRequestOutcome.declined,
      );
    });

    test('該当広場の申請が無ければgone（承認されて対象から外れた）', () {
      expect(joinRequestOutcome(const [], 'g1'), JoinRequestOutcome.gone);
      expect(
        joinRequestOutcome([req('g2', GroupJoinRequestStatus.pending)], 'g1'),
        JoinRequestOutcome.gone,
      );
    });
  });

  test('既に消えている削除の失敗（permission-denied/not-found）は成功扱い', () {
    expect(
      isAlreadyGoneError(
        FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'),
      ),
      isTrue,
    );
    expect(
      isAlreadyGoneError(
        FirebaseException(plugin: 'cloud_firestore', code: 'not-found'),
      ),
      isTrue,
    );
    // ネットワーク等は握らない。
    expect(
      isAlreadyGoneError(
        FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
      ),
      isFalse,
    );
    expect(isAlreadyGoneError(StateError('x')), isFalse);
  });
}
