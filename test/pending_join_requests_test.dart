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
}
