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
import '../models/group_role.dart';
import '../models/message.dart';
import '../utils/image_format.dart';

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

  /// この広場の寄合（テキストチャンネル）一覧を作成順に購読する。
  Stream<List<Room>> watchRooms(String groupId);

  /// 新しい寄合を作成する（長・モデレーターのみ、firestore.rulesで強制）。
  Future<Room> createRoom({required String groupId, required String name});

  /// 寄合を削除する。全メッセージも物理削除する（長・モデレーターのみ、
  /// firestore.rulesで強制）。その広場の最後の1つの寄合は削除できない
  /// （[StateError]を投げる）。削除対象が`Group.defaultRoomId`の場合は、
  /// 残った寄合のうち最も古いものに`defaultRoomId`を差し替える。
  Future<void> deleteRoom({
    required String groupId,
    required String roomId,
    required String requestedBy,
  });

  /// この広場のカスタムロール一覧を作成順に購読する（見た目専用、
  /// `memberRoles`＝長・モデレーター・メンバーという実際の権限区分とは無関係）。
  Stream<List<GroupRole>> watchRoles(String groupId);

  /// ロールを作成する（長・モデレーターのみ、firestore.rulesで強制）。
  Future<GroupRole> createRole({
    required String groupId,
    required String name,
    required int color,
  });

  /// ロールの名前・色を編集する（長・モデレーターのみ）。
  Future<void> updateRole({
    required String groupId,
    required String roleId,
    required String name,
    required int color,
  });

  /// ロールを削除する（長・モデレーターのみ）。このロールを付与されていた
  /// 全メンバーから、広場全体・寄合ごとの付与を問わず自動的に外す。
  Future<void> deleteRole({required String groupId, required String roleId});

  /// 広場全体でのロール付与を設定する（[roleId]がnullなら解除、
  /// 長・モデレーターのみ）。特定の寄合で[assignRoomRole]による付与が
  /// 別途されていれば、そちらが表示上優先される。
  Future<void> assignRole({
    required String groupId,
    required String userId,
    required String? roleId,
  });

  /// 特定の寄合限定でのロール付与を設定する（[roleId]がnullなら解除、
  /// 長・モデレーターのみ）。[assignRole]（広場全体の付与）より表示上優先される。
  Future<void> assignRoomRole({
    required String groupId,
    required String roomId,
    required String userId,
    required String? roleId,
  });

  /// [watchRoomMessages]の直近50件に含まれない古い返信先へジャンプする際に
  /// 使う。指定した[messageId]を含む前後合わせて最大[contextSize]*2件を
  /// 1回だけ取得する（購読はしない）。対象メッセージが既に削除済みの場合は
  /// 空を返す（`DirectMessageRepository.getMessagesAround`と同じ設計）。
  Future<List<Message>> getRoomMessagesAround({
    required String groupId,
    required String roomId,
    required String messageId,
    int contextSize = 25,
  });

  Future<void> sendRoomMessage({
    required String groupId,
    required String roomId,
    required String senderId,
    required String senderRhingId,
    required String content,
    bool silent = false,
    Message? replyTo,
  });

  /// 送信済みテキストメッセージの本文を編集する（本文編集のみ・時間制限なし）。
  Future<void> editRoomMessage({
    required String groupId,
    required String roomId,
    required String messageId,
    required String newContent,
  });

  /// 自分が送ったメッセージを、他のメンバーにも痕跡を残さず完全に削除する
  /// （物理削除）。このメッセージを引用返信している他のメッセージがあれば、
  /// それらのreplyTo系フィールドも同時にクリアする。
  Future<void> unsendRoomMessage({
    required String groupId,
    required String roomId,
    required String messageId,
  });

  /// 自分のリアクションを設定・解除する（[emoji]がnullなら解除、
  /// 既に設定済みでも上書きで乗り換えられる）。
  Future<void> setRoomMessageReaction({
    required String groupId,
    required String roomId,
    required String messageId,
    required String userId,
    String? emoji,
  });

  /// 指定したメッセージ群に、自分（[userId]）が読んだ記録を追加する。
  Future<void> markRoomMessagesRead({
    required String groupId,
    required String roomId,
    required String userId,
    required List<String> messageIds,
  });

  /// 選択したメッセージ群を、自分（[userId]）のアカウントから見えなくする
  /// （実際にはサーバーから削除せず、他のメンバーには引き続き見える）。
  /// お部屋のメンバー全員が同じメッセージを削除し終えた時点で、この呼び出しの
  /// 中でサーバーからも物理削除する（`DirectMessageRepository.hideMessagesForMe`
  /// と同じ設計）。
  Future<void> hideRoomMessagesForMe({
    required String groupId,
    required String roomId,
    required String userId,
    required List<String> messageIds,
  });

  /// 既読機能のオン/オフを切り替える（長のみ実行可能、firestore.rulesで
  /// 強制）。オフにする場合は、`defaultRoomId`の全メッセージ・全メンバー分の
  /// 既読履歴をサーバーから削除する。再度オンにした場合は新規メッセージの
  /// 既読記録が新たに始まる（過去分の復元はしない）。
  Future<void> setReadReceiptsEnabled({
    required String groupId,
    required bool enabled,
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

  /// 広場のプロフィールカード用背景画像をアップロードする。
  Future<GroupProfileCard> uploadProfileCardBackground({
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

  /// 自分が送った、承認待ちの参加リクエスト一覧（広場をまたいだcollection
  /// group検索）。語らいタブの広場一覧に「申請中」として表示するために使う。
  Stream<List<GroupJoinRequest>> watchMyPendingJoinRequests(String userId);

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
    await batch.commit();

    // groupInvitesのセキュリティルールはgroups/{groupId}を`get()`で参照して
    // memberIdsを判定するため、groupsのコミット完了後に別書き込みとして実行する
    // 必要がある（同一バッチ内だとget()が未コミットのgroupsを見られずpermission-deniedになる）。
    await _groupInvites.doc(groupRef.id).set(invitePreview.toJson());

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
  Stream<List<Room>> watchRooms(String groupId) {
    return _groups
        .doc(groupId)
        .collection('rooms')
        .orderBy('createdAt')
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => Room.fromJson(doc.id, doc.data())).toList());
  }

  @override
  Future<Room> createRoom({
    required String groupId,
    required String name,
  }) async {
    final group = await getGroup(groupId);
    if (group == null) throw StateError('広場が見つかりません');
    final roomRef = _groups.doc(groupId).collection('rooms').doc();
    final room = Room(
      roomId: roomRef.id,
      groupId: groupId,
      name: name,
      memberIds: group.memberIds,
    );
    await roomRef.set(room.toJson());
    return room;
  }

  @override
  Future<void> deleteRoom({
    required String groupId,
    required String roomId,
    required String requestedBy,
  }) async {
    final roomsSnapshot =
        await _groups.doc(groupId).collection('rooms').orderBy('createdAt').get();
    if (roomsSnapshot.docs.length <= 1) {
      throw StateError('最後の1つの寄合は削除できません');
    }

    final roomRef = _roomRef(groupId, roomId);
    // 削除の実行者を記録するマーカーを立てる。これを根拠に、以降の
    // メッセージ物理削除がfirestore.rules上許可される
    // （severance/既読オフと同じ「マーカー→カスケード削除」パターン）。
    await roomRef.update({'roomDeletionRequestedBy': requestedBy});

    final messagesRef = roomRef.collection('messages');
    while (true) {
      final snapshot = await messagesRef.limit(400).get();
      if (snapshot.docs.isEmpty) break;
      final batch = _firestore.batch();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    }
    await roomRef.delete();

    final group = await getGroup(groupId);
    if (group != null && group.defaultRoomId == roomId) {
      final remaining = roomsSnapshot.docs.where((d) => d.id != roomId).toList();
      if (remaining.isNotEmpty) {
        await _groups.doc(groupId).update({'defaultRoomId': remaining.first.id});
      }
    }
  }

  @override
  Stream<List<Message>> watchRoomMessages(String groupId, String roomId) {
    return _roomRef(groupId, roomId)
        .collection('messages')
        .orderBy('sentAt', descending: true)
        .limit(50)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => Message.fromJson(doc.id, doc.data()))
            .toList());
  }

  @override
  Future<List<Message>> getRoomMessagesAround({
    required String groupId,
    required String roomId,
    required String messageId,
    int contextSize = 25,
  }) async {
    final messagesRef = _roomRef(groupId, roomId).collection('messages');
    final targetDoc = await messagesRef.doc(messageId).get();
    final targetData = targetDoc.data();
    if (targetData == null) return [];
    final targetSentAt = targetData['sentAt'] as Timestamp?;
    if (targetSentAt == null) return [];

    final olderAndTarget = await messagesRef
        .orderBy('sentAt', descending: true)
        .where('sentAt', isLessThanOrEqualTo: targetSentAt)
        .limit(contextSize)
        .get();
    final newer = await messagesRef
        .orderBy('sentAt')
        .where('sentAt', isGreaterThan: targetSentAt)
        .limit(contextSize)
        .get();

    return [
      for (final doc in olderAndTarget.docs)
        Message.fromJson(doc.id, doc.data()),
      for (final doc in newer.docs) Message.fromJson(doc.id, doc.data()),
    ];
  }

  @override
  Future<void> sendRoomMessage({
    required String groupId,
    required String roomId,
    required String senderId,
    required String senderRhingId,
    required String content,
    bool silent = false,
    Message? replyTo,
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
      replyToMessageId: replyTo?.messageId,
      replyToSenderId: replyTo?.senderId,
      replyToSenderRhingId: replyTo?.senderRhingId,
      replyToSnippet: replyTo == null ? null : messageSnippetOf(replyTo.content),
    );

    final batch = _firestore.batch();
    batch.set(messageRef, message.toJson());
    batch.update(roomRef, {'lastMessageAt': FieldValue.serverTimestamp()});
    await batch.commit();
  }

  @override
  Future<void> editRoomMessage({
    required String groupId,
    required String roomId,
    required String messageId,
    required String newContent,
  }) async {
    await _roomRef(groupId, roomId).collection('messages').doc(messageId).update({
      'content': newContent,
      'editedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> unsendRoomMessage({
    required String groupId,
    required String roomId,
    required String messageId,
  }) async {
    final messagesRef = _roomRef(groupId, roomId).collection('messages');
    final quoting = await messagesRef
        .where('replyToMessageId', isEqualTo: messageId)
        .get();

    // 1件のメッセージへの引用返信が499件を超えることは現実的に想定しない
    // ため、500件のバッチ上限に収まる範囲でまとめて処理する
    // （本体の削除1件＋引用側の更新最大499件）。
    final batch = _firestore.batch();
    batch.delete(messagesRef.doc(messageId));
    for (final doc in quoting.docs.take(499)) {
      batch.update(doc.reference, {
        'replyToMessageId': FieldValue.delete(),
        'replyToSenderId': FieldValue.delete(),
        'replyToSenderRhingId': FieldValue.delete(),
        'replyToSnippet': FieldValue.delete(),
      });
    }
    await batch.commit();
  }

  @override
  Future<void> setRoomMessageReaction({
    required String groupId,
    required String roomId,
    required String messageId,
    required String userId,
    String? emoji,
  }) async {
    final ref = _roomRef(groupId, roomId).collection('messages').doc(messageId);
    await ref.update({
      'reactions.$userId': emoji ?? FieldValue.delete(),
    });
  }

  @override
  Future<void> markRoomMessagesRead({
    required String groupId,
    required String roomId,
    required String userId,
    required List<String> messageIds,
  }) async {
    if (messageIds.isEmpty) return;
    final messagesRef = _roomRef(groupId, roomId).collection('messages');
    final batch = _firestore.batch();
    // FieldValue.serverTimestamp()は配列要素の中では使えない（nullになる）ため、
    // クライアント側の時刻をそのまま記録する。
    final readAt = Timestamp.now();
    for (final messageId in messageIds) {
      batch.update(messagesRef.doc(messageId), {
        'readBy': FieldValue.arrayUnion([
          {'userId': userId, 'readAt': readAt},
        ]),
      });
    }
    await batch.commit();
  }

  @override
  Future<void> hideRoomMessagesForMe({
    required String groupId,
    required String roomId,
    required String userId,
    required List<String> messageIds,
  }) async {
    if (messageIds.isEmpty) return;
    final roomRef = _roomRef(groupId, roomId);
    final roomSnapshot = await roomRef.get();
    final memberIds = List<String>.from(
      roomSnapshot.data()?['memberIds'] as List? ?? const [],
    );
    final messagesRef = roomRef.collection('messages');

    // DirectMessageRepository.hideMessagesForMeと同じ設計（1件ずつgetして
    // 各メッセージのhiddenForを確認し、メンバー全員をカバーするなら物理削除、
    // そうでなければ自分を追加する更新に留める）。
    final docs = await Future.wait(
      messageIds.map((id) => messagesRef.doc(id).get()),
    );

    for (var i = 0; i < docs.length; i += 400) {
      final chunk = docs.sublist(i, i + 400 > docs.length ? docs.length : i + 400);
      final batch = _firestore.batch();
      for (final doc in chunk) {
        if (!doc.exists) continue;
        final hiddenFor = {
          ...?(doc.data()?['hiddenFor'] as List?)?.cast<String>(),
          userId,
        };
        if (memberIds.every(hiddenFor.contains)) {
          batch.delete(doc.reference);
        } else {
          batch.update(doc.reference, {
            'hiddenFor': FieldValue.arrayUnion([userId]),
          });
        }
      }
      await batch.commit();
    }
  }

  @override
  Future<void> setReadReceiptsEnabled({
    required String groupId,
    required bool enabled,
  }) async {
    final group = await getGroup(groupId);
    if (group == null) return;
    await _groups.doc(groupId).update({'readReceiptsEnabled': enabled});
    if (!enabled) {
      final roomsSnapshot = await _groups.doc(groupId).collection('rooms').get();
      for (final roomDoc in roomsSnapshot.docs) {
        await _clearAllReadReceipts(roomDoc.reference.collection('messages'));
      }
    }
  }

  /// [messagesRef]配下の全メッセージの既読履歴（readBy）を空にする。
  /// 更新後もドキュメントは残り続けるため、`acceptSeverance`の
  /// （削除により毎回別集合が返ってくる）`.limit(400)`繰り返し取得とは
  /// 異なり、カーソルで明示的にページを進める必要がある。
  Future<void> _clearAllReadReceipts(
    CollectionReference<Map<String, dynamic>> messagesRef,
  ) async {
    DocumentSnapshot<Map<String, dynamic>>? cursor;
    while (true) {
      var query = messagesRef.orderBy(FieldPath.documentId).limit(400);
      if (cursor != null) query = query.startAfterDocument(cursor);
      final snapshot = await query.get();
      if (snapshot.docs.isEmpty) break;
      final batch = _firestore.batch();
      for (final doc in snapshot.docs) {
        final readBy = doc.data()['readBy'] as List<dynamic>? ?? const [];
        if (readBy.isNotEmpty) {
          batch.update(doc.reference, {'readBy': <Map<String, dynamic>>[]});
        }
      }
      await batch.commit();
      cursor = snapshot.docs.last;
      if (snapshot.docs.length < 400) break;
    }
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
      backgroundImageUrl: card.backgroundImageUrl,
    );
    final batch = _firestore.batch();
    // カード名は広場の実際の名前（Group.name）と同一の値として扱う。
    // カード編集画面から名前を変更したら、実際の広場名にも反映する
    // （firestore.rulesのgroups更新許可もprofileCardと同時のnameの変更を
    // 許すよう対応済み）。
    batch.update(_groups.doc(groupId), {
      'profileCard': card.toJson(),
      'name': card.name,
    });
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
    // GIFはWebPに圧縮するとアニメーションが失われるため、圧縮をスキップして
    // 元のバイトのままアップロードする（user_repository.dartの同様の処理を参照）。
    final isGif = isGifBytes(bytes);
    final compressed = isGif ? null : await _tryCompressToWebp(bytes);
    final String extension;
    final String contentType;
    if (isGif) {
      extension = 'gif';
      contentType = 'image/gif';
    } else if (compressed != null) {
      extension = 'webp';
      contentType = 'image/webp';
    } else {
      extension = 'jpg';
      contentType = 'image/jpeg';
    }
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

  @override
  Future<GroupProfileCard> uploadProfileCardBackground({
    required String groupId,
    required GroupProfileCard card,
    required Uint8List bytes,
  }) async {
    final id = _groups.doc().id;
    final isGif = isGifBytes(bytes);
    final compressed = isGif ? null : await _tryCompressToWebp(bytes);
    final String extension;
    final String contentType;
    if (isGif) {
      extension = 'gif';
      contentType = 'image/gif';
    } else if (compressed != null) {
      extension = 'webp';
      contentType = 'image/webp';
    } else {
      extension = 'jpg';
      contentType = 'image/jpeg';
    }
    final path = 'groupBackgrounds/$groupId/$id.$extension';
    final ref = _storage.ref(path);
    await ref.putData(
      compressed ?? bytes,
      SettableMetadata(contentType: contentType),
    );
    final url = await ref.getDownloadURL();

    // 差し替え前の背景画像が残っていれば削除する（ストレージの肥大化防止）。
    final previousPath = card.backgroundImageStoragePath;
    if (previousPath != null) {
      try {
        await _storage.ref(previousPath).delete();
      } catch (_) {
        // 削除失敗はアップロード自体の成否に影響させない。
      }
    }

    return card.copyWith(
      backgroundImageUrl: url,
      backgroundImageStoragePath: path,
    );
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
  Stream<List<GroupJoinRequest>> watchMyPendingJoinRequests(String userId) {
    return _firestore
        .collectionGroup('joinRequests')
        .where('requesterId', isEqualTo: userId)
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

    final roomsSnapshot =
        await _groups.doc(request.groupId).collection('rooms').get();

    final batch = _firestore.batch();
    batch.update(requestRef, {
      'status': GroupJoinRequestStatus.accepted.name,
      'respondedAt': FieldValue.serverTimestamp(),
    });
    batch.update(groupRef, {
      'memberIds': FieldValue.arrayUnion([request.requesterId]),
      'memberRoles': {...group.memberRoles, request.requesterId: 'member'},
    });
    for (final roomDoc in roomsSnapshot.docs) {
      batch.update(roomDoc.reference, {
        'memberIds': FieldValue.arrayUnion([request.requesterId]),
      });
    }
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
    final roomsSnapshot = await _groups.doc(groupId).collection('rooms').get();

    final batch = _firestore.batch();
    batch.update(groupRef, {
      'memberIds': FieldValue.arrayRemove([userId]),
      'memberRoles': updatedRoles,
    });
    for (final roomDoc in roomsSnapshot.docs) {
      batch.update(roomDoc.reference, {
        'memberIds': FieldValue.arrayRemove([userId]),
      });
    }
    await batch.commit();
  }

  CollectionReference<Map<String, dynamic>> _rolesOf(String groupId) =>
      _groups.doc(groupId).collection('roles');

  @override
  Stream<List<GroupRole>> watchRoles(String groupId) {
    return _rolesOf(groupId).orderBy('createdAt').snapshots().map(
          (snapshot) => snapshot.docs
              .map((doc) => GroupRole.fromJson(doc.id, doc.data()))
              .toList(),
        );
  }

  @override
  Future<GroupRole> createRole({
    required String groupId,
    required String name,
    required int color,
  }) async {
    final roleRef = _rolesOf(groupId).doc();
    final role = GroupRole(
      roleId: roleRef.id,
      groupId: groupId,
      name: name,
      color: color,
    );
    await roleRef.set(role.toJson());
    return role;
  }

  @override
  Future<void> updateRole({
    required String groupId,
    required String roleId,
    required String name,
    required int color,
  }) async {
    await _rolesOf(groupId).doc(roleId).update({'name': name, 'color': color});
  }

  @override
  Future<void> deleteRole({
    required String groupId,
    required String roleId,
  }) async {
    await _rolesOf(groupId).doc(roleId).delete();

    // このロールが付与されていたメンバーから外す（広場全体・寄合ごとの
    // 付与の両方）。付与はuserId->roleIdのマップのため、削除対象を
    // 一度読み込んで値で絞り込む必要がある。
    final groupRef = _groups.doc(groupId);
    final groupDoc = await groupRef.get();
    final groupAssignments =
        Map<String, dynamic>.from(groupDoc.data()?['roleAssignments'] as Map? ?? {});
    final groupUpdate = <String, dynamic>{
      for (final entry in groupAssignments.entries)
        if (entry.value == roleId) 'roleAssignments.${entry.key}': FieldValue.delete(),
    };
    if (groupUpdate.isNotEmpty) await groupRef.update(groupUpdate);

    final roomsSnapshot = await groupRef.collection('rooms').get();
    for (final roomDoc in roomsSnapshot.docs) {
      final roomAssignments =
          Map<String, dynamic>.from(roomDoc.data()['roleAssignments'] as Map? ?? {});
      final roomUpdate = <String, dynamic>{
        for (final entry in roomAssignments.entries)
          if (entry.value == roleId) 'roleAssignments.${entry.key}': FieldValue.delete(),
      };
      if (roomUpdate.isNotEmpty) await roomDoc.reference.update(roomUpdate);
    }
  }

  @override
  Future<void> assignRole({
    required String groupId,
    required String userId,
    required String? roleId,
  }) async {
    await _groups.doc(groupId).update({
      'roleAssignments.$userId': roleId ?? FieldValue.delete(),
    });
  }

  @override
  Future<void> assignRoomRole({
    required String groupId,
    required String roomId,
    required String userId,
    required String? roleId,
  }) async {
    await _roomRef(groupId, roomId).update({
      'roleAssignments.$userId': roleId ?? FieldValue.delete(),
    });
  }
}
