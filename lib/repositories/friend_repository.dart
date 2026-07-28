import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/app_user.dart';
import '../models/direct_message.dart';
import '../models/dm_room.dart';
import '../models/friend.dart';
import '../models/friend_request.dart';

/// 友達申請と友達関係を扱うリポジトリ。
/// 友達になるまでの流れ: IDで検索 → 申請を送る → 相手が承認する → 一対で会話できるようになる。
abstract class FriendRepository {
  /// [from]から[to]へ友達申請を送る。
  /// 既に相手からの申請が届いている場合は、それを承認する（相互申請での即成立）。
  /// 既に友達、または自分からの申請が返答待ちの場合は何もしない。
  Future<void> sendRequest({required AppUser from, required AppUser to});

  /// 自分宛の返答待ち申請一覧。
  Stream<List<FriendRequest>> watchIncomingRequests(String userId);

  /// 自分が送った返答待ち申請一覧。
  Stream<List<FriendRequest>> watchOutgoingRequests(String userId);

  /// 申請に応答する。承認の場合は双方の友達関係と一対を作成する。
  Future<void> respond({
    required FriendRequest request,
    required bool accept,
  });

  /// 自分の友達一覧。
  Stream<List<Friend>> watchFriends(String userId);

  Future<bool> isFriend({required String userId, required String otherUserId});

  /// 2人の間の友達申請ドキュメントを1回だけ取得する（無ければnull）。
  /// 相手のプロフィールカードを開いた際に、既に友達か・申請中か・
  /// 相手から申請が届いているかを判定するために使う。
  Future<FriendRequest?> getRequest(String userIdA, String userIdB);
}

class FirestoreFriendRepository implements FriendRepository {
  FirestoreFriendRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _requests =>
      _firestore.collection('friendRequests');

  CollectionReference<Map<String, dynamic>> _friendsOf(String userId) =>
      _firestore.collection('users').doc(userId).collection('friends');

  @override
  Future<void> sendRequest({required AppUser from, required AppUser to}) async {
    final requestId = FriendRequest.idFor(from.userId, to.userId);
    final ref = _requests.doc(requestId);
    final doc = await ref.get();

    if (!doc.exists) {
      final request = FriendRequest(
        requestId: requestId,
        fromUserId: from.userId,
        fromRhingId: from.rhingId,
        toUserId: to.userId,
        toRhingId: to.rhingId,
        status: FriendRequestStatus.pending,
      );
      await ref.set(request.toJson());
      return;
    }

    final existing = FriendRequest.fromJson(requestId, doc.data()!);
    if (existing.status == FriendRequestStatus.accepted) {
      // statusがaccepted のままでも、絶縁等で実際のfriendsサブコレクションが
      // 既に削除されている場合がある（friendRequestsドキュメント自体は
      // 削除される設計だが、念のためここでも実データを見て判定する）。
      // 実際にまだ友達なら何もしない。友達でなければ下の再申請処理へ進む。
      final stillFriends =
          await isFriend(userId: from.userId, otherUserId: to.userId);
      if (stillFriends) return;
    } else if (existing.status == FriendRequestStatus.pending) {
      if (existing.fromUserId == from.userId) {
        return; // 既に自分から送信済み・返答待ち
      }
      // 相手からの申請が届いていた＝相互に追加しようとした。その場で承認扱いにする。
      await respond(request: existing, accept: true);
      return;
    }
    // declined、またはaccepted済みだが実際は友達ではない場合: 再申請として上書きする。
    final request = FriendRequest(
      requestId: requestId,
      fromUserId: from.userId,
      fromRhingId: from.rhingId,
      toUserId: to.userId,
      toRhingId: to.rhingId,
      status: FriendRequestStatus.pending,
    );
    await ref.set(request.toJson());
  }

  @override
  Stream<List<FriendRequest>> watchIncomingRequests(String userId) {
    return _requests
        .where('toUserId', isEqualTo: userId)
        .where('status', isEqualTo: FriendRequestStatus.pending.name)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => FriendRequest.fromJson(doc.id, doc.data()))
            .toList());
  }

  @override
  Stream<List<FriendRequest>> watchOutgoingRequests(String userId) {
    return _requests
        .where('fromUserId', isEqualTo: userId)
        .where('status', isEqualTo: FriendRequestStatus.pending.name)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => FriendRequest.fromJson(doc.id, doc.data()))
            .toList());
  }

  @override
  Future<void> respond({
    required FriendRequest request,
    required bool accept,
  }) async {
    final ref = _requests.doc(request.requestId);

    if (!accept) {
      await ref.update({
        'status': FriendRequestStatus.declined.name,
        'respondedAt': FieldValue.serverTimestamp(),
      });
      return;
    }

    // friendRequestsの承認を先に確定させてから友達関係・一対を作る。
    // （Firestoreルールがdirectメッセージ/friends作成時にこのステータスを参照するため、
    //   同じバッチ内で先に依存させるより、確定後の別コミットにする方が確実）
    await ref.update({
      'status': FriendRequestStatus.accepted.name,
      'respondedAt': FieldValue.serverTimestamp(),
    });

    final dmId = DirectMessage.idFor(request.fromUserId, request.toUserId);
    final dmRef = _firestore.collection('directMessages').doc(dmId);
    final roomRef = dmRef.collection('rooms').doc();
    final participants = [request.fromUserId, request.toUserId];
    final dm = DirectMessage(
      dmId: dmId,
      participants: participants,
      participantRhingIds: {
        request.fromUserId: request.fromRhingId,
        request.toUserId: request.toRhingId,
      },
      defaultRoomId: roomRef.id,
    );
    final room = DmRoom(
      roomId: roomRef.id,
      dmId: dmId,
      name: 'メイン',
      participants: participants,
    );

    final batch = _firestore.batch();
    batch.set(
      _friendsOf(request.fromUserId).doc(request.toUserId),
      Friend(
        friendUserId: request.toUserId,
        friendRhingId: request.toRhingId,
      ).toJson(),
    );
    batch.set(
      _friendsOf(request.toUserId).doc(request.fromUserId),
      Friend(
        friendUserId: request.fromUserId,
        friendRhingId: request.fromRhingId,
      ).toJson(),
    );
    batch.set(dmRef, dm.toJson());
    batch.set(roomRef, room.toJson());
    await batch.commit();
  }

  @override
  Stream<List<Friend>> watchFriends(String userId) {
    return _friendsOf(userId).snapshots().map((snapshot) => snapshot.docs
        .map((doc) => Friend.fromJson(doc.id, doc.data()))
        .toList());
  }

  @override
  Future<bool> isFriend({
    required String userId,
    required String otherUserId,
  }) async {
    final doc = await _friendsOf(userId).doc(otherUserId).get();
    return doc.exists;
  }

  @override
  Future<FriendRequest?> getRequest(String userIdA, String userIdB) async {
    final requestId = FriendRequest.idFor(userIdA, userIdB);
    final doc = await _requests.doc(requestId).get();
    if (!doc.exists) return null;
    return FriendRequest.fromJson(requestId, doc.data()!);
  }
}
