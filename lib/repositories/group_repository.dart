import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_image_compress/flutter_image_compress.dart';

import '../models/app_user.dart';
import '../models/group.dart';
import '../models/group_invite_preview.dart';
import '../models/group_join_request.dart';
import '../models/group_profile_card.dart';
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

  /// 広場を1件取得する。メンバーでない場合はFirestoreルールにより
  /// permission-deniedとなるため、その場合はnullを返す
  /// （招待リンクを開いた相手が「既にメンバーかどうか」を判定するのに使う）。
  Future<Group?> getGroup(String groupId);

  Stream<List<Message>> watchRoomMessages(String groupId, String roomId);

  Future<void> sendRoomMessage({
    required String groupId,
    required String roomId,
    required String senderId,
    required String senderRhingId,
    required String content,
    bool silent = false,
  });

  /// 広場のプロフィールカードを作成・更新する。メンバー全員が実行できる。
  Future<void> updateProfileCard({
    required String groupId,
    required GroupProfileCard card,
  });

  /// 広場のプロフィールカード用アイコンをアップロードする。
  Future<GroupProfileCard> uploadProfileCardIcon({
    required String groupId,
    required GroupProfileCard card,
    required Uint8List bytes,
  });

  /// 招待リンク・QRコードから開いた相手に見せる、広場の公開プレビュー
  /// （名前・アイコン・説明のみ。メンバー一覧やメッセージは含まない）。
  /// ログイン前・非メンバーでも読み取れる。
  Future<GroupInvitePreview?> getInvitePreview(String groupId);

  /// 広場への参加をリクエストする（長・モデレーターの承認待ちになる）。
  Future<void> requestToJoin({
    required String groupId,
    required AppUser requester,
  });

  /// 自分が送った参加リクエストの状態を取得する（未送信ならnull）。
  Future<GroupJoinRequest?> getJoinRequest({
    required String groupId,
    required String requesterId,
  });

  /// 承認待ちの参加リクエスト一覧（長・モデレーターが見る）。
  Stream<List<GroupJoinRequest>> watchJoinRequests(String groupId);

  /// 参加リクエストに応答する。承認の場合はメンバーとして追加する。
  Future<void> respondToJoinRequest({
    required GroupJoinRequest request,
    required bool accept,
  });

  /// 広場から退会する。オーナーは退会できない。
  Future<void> leaveGroup({required String groupId, required String userId});
}

class FirestoreGroupRepository implements GroupRepository {
  FirestoreGroupRepository({FirebaseFirestore? firestore, FirebaseStorage? storage})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _storage = storage ?? FirebaseStorage.instance;

  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;

  CollectionReference<Map<String, dynamic>> get _groups =>
      _firestore.collection('groups');

  CollectionReference<Map<String, dynamic>> get _groupInvites =>
      _firestore.collection('groupInvites');

  CollectionReference<Map<String, dynamic>> _joinRequestsOf(String groupId) =>
      _groups.doc(groupId).collection('joinRequests');

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

    final invitePreview = GroupInvitePreview(name: name);

    final batch = _firestore.batch();
    batch.set(groupRef, group.toJson());
    batch.set(roomRef, room.toJson());
    batch.set(_groupInvites.doc(groupRef.id), invitePreview.toJson());
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

  @override
  Future<Group?> getGroup(String groupId) async {
    try {
      final doc = await _groups.doc(groupId).get();
      if (!doc.exists) return null;
      return Group.fromJson(doc.id, doc.data()!);
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') return null;
      rethrow;
    }
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
    required String senderRhingId,
    required String content,
    bool silent = false,
  }) async {
    final roomRef = _roomRef(groupId, roomId);
    final messageRef = roomRef.collection('messages').doc();

    final message = Message(
      messageId: messageRef.id,
      conversationId: roomId,
      conversationType: 'room',
      senderId: senderId,
      senderRhingId: senderRhingId,
      content: content,
      contentType: 'text',
      silent: silent,
    );

    final batch = _firestore.batch();
    batch.set(messageRef, message.toJson());
    batch.update(roomRef, {'lastMessageAt': FieldValue.serverTimestamp()});
    await batch.commit();
  }

  @override
  Future<void> updateProfileCard({
    required String groupId,
    required GroupProfileCard card,
  }) async {
    final preview = GroupInvitePreview(
      name: card.name,
      description: card.description,
      iconUrl: card.iconUrl,
    );
    final batch = _firestore.batch();
    batch.update(_groups.doc(groupId), {'profileCard': card.toJson()});
    batch.set(_groupInvites.doc(groupId), preview.toJson());
    await batch.commit();
  }

  @override
  Future<GroupProfileCard> uploadProfileCardIcon({
    required String groupId,
    required GroupProfileCard card,
    required Uint8List bytes,
  }) async {
    final id = _groups.doc().id;
    final compressed = await _tryCompressToWebp(bytes);
    final extension = compressed != null ? 'webp' : 'jpg';
    final contentType = compressed != null ? 'image/webp' : 'image/jpeg';
    final path = 'groupIcons/$groupId/$id.$extension';
    final ref = _storage.ref(path);
    await ref.putData(
      compressed ?? bytes,
      SettableMetadata(contentType: contentType),
    );
    final url = await ref.getDownloadURL();

    // 差し替え前のアイコンが残っていれば削除する（ストレージの肥大化防止）。
    final previousPath = card.iconStoragePath;
    if (previousPath != null) {
      try {
        await _storage.ref(previousPath).delete();
      } catch (_) {
        // 削除失敗はアップロード自体の成否に影響させない。
      }
    }

    return card.copyWith(iconUrl: url, iconStoragePath: path);
  }

  Future<Uint8List?> _tryCompressToWebp(Uint8List bytes) async {
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) return null;
    try {
      return await FlutterImageCompress.compressWithList(
        bytes,
        minWidth: 512,
        minHeight: 512,
        quality: 85,
        format: CompressFormat.webp,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<GroupInvitePreview?> getInvitePreview(String groupId) async {
    final doc = await _groupInvites.doc(groupId).get();
    if (!doc.exists) return null;
    return GroupInvitePreview.fromJson(doc.data()!);
  }

  @override
  Future<void> requestToJoin({
    required String groupId,
    required AppUser requester,
  }) async {
    final request = GroupJoinRequest(
      requestId: requester.userId,
      groupId: groupId,
      requesterId: requester.userId,
      requesterRhingId: requester.rhingId,
      status: GroupJoinRequestStatus.pending,
    );
    await _joinRequestsOf(groupId).doc(requester.userId).set(request.toJson());
  }

  @override
  Future<GroupJoinRequest?> getJoinRequest({
    required String groupId,
    required String requesterId,
  }) async {
    final doc = await _joinRequestsOf(groupId).doc(requesterId).get();
    if (!doc.exists) return null;
    return GroupJoinRequest.fromJson(doc.id, doc.data()!);
  }

  @override
  Stream<List<GroupJoinRequest>> watchJoinRequests(String groupId) {
    return _joinRequestsOf(groupId)
        .where('status', isEqualTo: GroupJoinRequestStatus.pending.name)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => GroupJoinRequest.fromJson(doc.id, doc.data()))
            .toList());
  }

  @override
  Future<void> respondToJoinRequest({
    required GroupJoinRequest request,
    required bool accept,
  }) async {
    final requestRef = _joinRequestsOf(request.groupId).doc(request.requestId);

    if (!accept) {
      await requestRef.update({
        'status': GroupJoinRequestStatus.declined.name,
        'respondedAt': FieldValue.serverTimestamp(),
      });
      return;
    }

    final groupRef = _groups.doc(request.groupId);
    final groupDoc = await groupRef.get();
    final group = Group.fromJson(groupRef.id, groupDoc.data()!);
    if (group.memberIds.contains(request.requesterId)) {
      // 既にメンバー（重複承認）。リクエストの状態だけ確定させる。
      await requestRef.update({
        'status': GroupJoinRequestStatus.accepted.name,
        'respondedAt': FieldValue.serverTimestamp(),
      });
      return;
    }

    final roomRef = _roomRef(request.groupId, group.defaultRoomId);

    final batch = _firestore.batch();
    batch.update(requestRef, {
      'status': GroupJoinRequestStatus.accepted.name,
      'respondedAt': FieldValue.serverTimestamp(),
    });
    batch.update(groupRef, {
      'memberIds': FieldValue.arrayUnion([request.requesterId]),
      'memberRoles': {...group.memberRoles, request.requesterId: 'member'},
    });
    batch.update(roomRef, {
      'memberIds': FieldValue.arrayUnion([request.requesterId]),
    });
    await batch.commit();
  }

  @override
  Future<void> leaveGroup({
    required String groupId,
    required String userId,
  }) async {
    final groupRef = _groups.doc(groupId);
    final groupDoc = await groupRef.get();
    final group = Group.fromJson(groupRef.id, groupDoc.data()!);
    if (group.ownerId == userId) {
      throw StateError('オーナーは退会できません');
    }

    final updatedRoles = {...group.memberRoles}..remove(userId);
    final roomRef = _roomRef(groupId, group.defaultRoomId);

    final batch = _firestore.batch();
    batch.update(groupRef, {
      'memberIds': FieldValue.arrayRemove([userId]),
      'memberRoles': updatedRoles,
    });
    batch.update(roomRef, {
      'memberIds': FieldValue.arrayRemove([userId]),
    });
    await batch.commit();
  }
}
