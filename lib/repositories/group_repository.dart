import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/app_user.dart';
import '../models/group.dart';
import '../models/message.dart';

abstract class GroupRepository {
  /// 広場を作成する。作成者がowner、他のメンバーはmemberとして登録され、
  /// 会話用のお部屋（デフォルトルーム）を1つ自動で作成する。
  Future<Group> createGroup({
    required String name,
    required AppUser owner,
    required List<AppUser> members,
  });

  /// 自分が参加している広場一覧を取得する。
  Stream<List<Group>> watchGroups(String userId);

  Stream<List<Message>> watchRoomMessages(String groupId, String roomId);

  Future<void> sendRoomMessage({
    required String groupId,
    required String roomId,
    required String senderId,
    required String content,
  });
}

class FirestoreGroupRepository implements GroupRepository {
  FirestoreGroupRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _groups =>
      _firestore.collection('groups');

  @override
  Future<Group> createGroup({
    required String name,
    required AppUser owner,
    required List<AppUser> members,
  }) async {
    final groupRef = _groups.doc();
    final roomRef = groupRef.collection('rooms').doc();

    final memberIds = [owner.userId, ...members.map((m) => m.userId)];
    final memberRoles = <String, String>{
      owner.userId: 'owner',
      for (final member in members) member.userId: 'member',
    };

    final group = Group(
      groupId: groupRef.id,
      name: name,
      ownerId: owner.userId,
      memberIds: memberIds,
      memberRoles: memberRoles,
      defaultRoomId: roomRef.id,
    );

    final room = Room(
      roomId: roomRef.id,
      groupId: groupRef.id,
      name: 'メイン',
      memberIds: memberIds,
    );

    final batch = _firestore.batch();
    batch.set(groupRef, group.toJson());
    batch.set(roomRef, room.toJson());
    await batch.commit();

    return group;
  }

  @override
  Stream<List<Group>> watchGroups(String userId) {
    return _groups
        .where('memberIds', arrayContains: userId)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => Group.fromJson(doc.id, doc.data()))
            .toList());
  }

  DocumentReference<Map<String, dynamic>> _roomRef(
    String groupId,
    String roomId,
  ) {
    return _groups.doc(groupId).collection('rooms').doc(roomId);
  }

  @override
  Stream<List<Message>> watchRoomMessages(String groupId, String roomId) {
    return _roomRef(groupId, roomId)
        .collection('messages')
        .where('deletedAt', isNull: true)
        .orderBy('sentAt', descending: true)
        .limit(50)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => Message.fromJson(doc.id, doc.data()))
            .toList());
  }

  @override
  Future<void> sendRoomMessage({
    required String groupId,
    required String roomId,
    required String senderId,
    required String content,
  }) async {
    final roomRef = _roomRef(groupId, roomId);
    final messageRef = roomRef.collection('messages').doc();

    final message = Message(
      messageId: messageRef.id,
      conversationId: roomId,
      conversationType: 'room',
      senderId: senderId,
      content: content,
      contentType: 'text',
    );

    final batch = _firestore.batch();
    batch.set(messageRef, message.toJson());
    batch.update(roomRef, {'lastMessageAt': FieldValue.serverTimestamp()});
    await batch.commit();
  }
}
