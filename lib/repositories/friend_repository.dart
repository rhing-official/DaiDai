import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../models/app_user.dart';
import '../models/direct_message.dart';
import '../models/dm_room.dart';
import '../models/friend.dart';
import '../models/friend_request.dart';

/// 友達申請と友達関係を扱うリポジトリ。
/// 友達になるまでの流れ: IDで検索 → 申請を送る → 相手が承認する → 一対で会話できるようになる。
abstract class FriendRepository {
  /// [from]から[to]へ友達申請を送る。[message]は任意の同梱メッセージ
  /// （100文字まで、技術仕様書8.3レイヤー2）。
  /// 既に相手からの申請が届いている場合は、それを承認する（相互申請での即成立）。
  /// 既に友達、または自分からの申請が返答待ちの場合は何もしない。
  ///
  /// レート制限（技術仕様書8.3レイヤー1）を超えた場合・[message]が長すぎる
  /// 場合・同一内容を短時間に大量送信しようとした場合は
  /// [FirebaseFunctionsException]を投げる。
  Future<void> sendRequest({
    required AppUser from,
    required AppUser to,
    String? message,
  });

  /// 自分宛の返答待ち申請一覧。
  Stream<List<FriendRequest>> watchIncomingRequests(String userId);

  /// 自分が送った返答待ち申請一覧。
  Stream<List<FriendRequest>> watchOutgoingRequests(String userId);

  /// 申請に応答する。承認の場合は双方の友達関係と一対を作成する。
  Future<void> respond({required FriendRequest request, required bool accept});

  /// 自分の友達一覧。
  Stream<List<Friend>> watchFriends(String userId);

  Future<bool> isFriend({required String userId, required String otherUserId});

  /// 2人の間の友達申請ドキュメントを1回だけ取得する（無ければnull）。
  /// 相手のプロフィールカードを開いた際に、既に友達か・申請中か・
  /// 相手から申請が届いているかを判定するために使う。
  Future<FriendRequest?> getRequest(String userIdA, String userIdB);
}

class FirestoreFriendRepository implements FriendRepository {
  FirestoreFriendRepository({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _functions =
           functions ??
           FirebaseFunctions.instanceFor(region: 'asia-northeast1');

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;

  CollectionReference<Map<String, dynamic>> get _requests =>
      _firestore.collection('friendRequests');

  CollectionReference<Map<String, dynamic>> _friendsOf(String userId) =>
      _firestore.collection('users').doc(userId).collection('friends');

  @override
  Future<void> sendRequest({
    required AppUser from,
    required AppUser to,
    String? message,
  }) async {
    // 技術仕様書8.3レイヤー1（送信頻度のレート制限）・レイヤー2（同梱
    // メッセージの文字数・同一内容の大量送信検知）をクライアント側の
    // 直接書き込みでは強制できないため、Cloud Functionsのcallableに
    // 寄せている（`suspendUserAccount`等と同じAdmin SDK経由のパターン、
    // 2026-09-07）。分岐ロジック（新規送信／相互申請の即時承認／
    // 拒否後の再送信）自体はこのファイルの旧`sendRequest`実装と
    // 同じ内容を関数側（`functions/src/index.ts`の`sendFriendRequest`）に
    // 移植している。
    await _functions.httpsCallable('sendFriendRequest').call({
      'fromUserId': from.userId,
      'fromRhingId': from.rhingId,
      'toUserId': to.userId,
      'toRhingId': to.rhingId,
      'message': message,
    });
  }

  @override
  Stream<List<FriendRequest>> watchIncomingRequests(String userId) {
    return _requests
        .where('toUserId', isEqualTo: userId)
        .where('status', isEqualTo: FriendRequestStatus.pending.name)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => FriendRequest.fromJson(doc.id, doc.data()))
              .toList(),
        );
  }

  @override
  Stream<List<FriendRequest>> watchOutgoingRequests(String userId) {
    return _requests
        .where('fromUserId', isEqualTo: userId)
        .where('status', isEqualTo: FriendRequestStatus.pending.name)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => FriendRequest.fromJson(doc.id, doc.data()))
              .toList(),
        );
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
      // 一対は常に単一モードで作られる（GroupのroomsEnabledと同じ考え方、
      // 2026-07-29追加）。後からハンバーガーメニューの「寄合を増やす」で
      // 複数モードに切り替えられる。
      roomsEnabled: false,
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
    return _friendsOf(userId).snapshots().map(
      (snapshot) => snapshot.docs
          .map((doc) => Friend.fromJson(doc.id, doc.data()))
          .toList(),
    );
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
