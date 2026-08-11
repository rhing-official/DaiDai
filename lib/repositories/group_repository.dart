import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:collection/collection.dart';
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
import '../utils/attachment_upload.dart';
import '../utils/image_format.dart';

abstract class GroupRepository {
  /// 広場を作成する。作成者がowner、他のメンバーはmemberとして登録され、
  /// 会話用のお部屋（デフォルトルーム）を1つ自動で作成する。
  Future<Group> createGroup({
    required String name,
    required AppUser owner,
    required List<AppUser> members,
    required bool roomsEnabled,
  });

  /// 自分が参加している広場一覧を取得する。
  Stream<List<Group>> watchGroups(String userId);

  /// 広場を1件取得する。メンバーでない場合はFirestoreルールにより
  /// permission-deniedとなるため、その場合はnullを返す
  /// （招待リンクを開いた相手が「既にメンバーかどうか」を判定するのに使う）。
  Future<Group?> getGroup(String groupId);

  /// 広場1件をリアルタイムに購読する（`GroupRoleListPopup`等、開いている間も
  /// `rolePriority`等の変更を反映する必要がある画面で使う、2026-07-29追加）。
  Stream<Group?> watchGroup(String groupId);

  Stream<List<Message>> watchRoomMessages(String groupId, String roomId);

  /// この広場の寄合（テキストチャンネル）一覧を作成順に購読する。[userId]は
  /// 呼び出し元本人のuserId（firestore.rulesの`list`操作は、クエリ自体に
  /// ルールと同じ条件の`where`句が無いと「結果に含まれ得る全ドキュメントが
  /// ルールを満たすと証明できない」として要求全体を拒否するため、
  /// クエリ側にも`memberIds`のarray-contains条件を付ける必要がある）。
  Stream<List<Room>> watchRooms({
    required String groupId,
    required String userId,
  });

  /// 新しい寄合を作成する（長・モデレーターのみ、firestore.rulesで強制）。
  Future<Room> createRoom({required String groupId, required String name});

  /// 寄合の名前を変更する（manageRooms権限を持つメンバーのみ、
  /// firestore.rulesで強制）。
  Future<void> renameRoom({
    required String groupId,
    required String roomId,
    required String name,
  });

  /// 単一モードの広場を複数モードに切り替える、または複数モードの広場を
  /// 単一モードに戻す（どちらもmanageRooms権限を持つメンバーのみ、
  /// firestore.rulesで強制）。単一に戻す場合（[enabled] == false）は
  /// 寄合が1つだけの場合に限り許可し、それ以外では[StateError]を投げる
  /// （[requestedBy]必須、全体設定から呼ぶ、2026-07-29追加。以前はtrueへの
  /// 変更しかできなかった）。
  Future<void> setRoomsEnabled({
    required String groupId,
    required bool enabled,
    String? requestedBy,
  });

  /// 寄合を削除する。全メッセージも物理削除する（長・モデレーターのみ、
  /// firestore.rulesで強制）。その広場の最後の1つの寄合は削除できない
  /// （[StateError]を投げる）。削除対象が`Group.defaultRoomId`の場合は、
  /// 残った寄合のうち最も古いものに`defaultRoomId`を差し替える。
  Future<void> deleteRoom({
    required String groupId,
    required String roomId,
    required String requestedBy,
  });

  /// この広場のカスタムロール一覧を作成順に購読する。長のみ持つ全権限は
  /// ロールとは別枠（[Group.ownerId]）で扱う。基準ロール（[GroupRole.isEveryone]）
  /// が必ず1件含まれる。
  Stream<List<GroupRole>> watchRoles(String groupId);

  /// ロールを作成する（`GroupPermission.manageRoles`を持つメンバーのみ、
  /// firestore.rulesで強制）。成功後、広場全体の優先順位（[Group.rolePriority]）の
  /// 最後尾に自動で追加される。
  Future<GroupRole> createRole({
    required String groupId,
    required String name,
    required int? color,
    required Set<String> permissions,
  });

  /// ロールの名前・色・権限を編集する（`GroupPermission.manageRoles`が必要）。
  /// 基準ロール（[GroupRole.isEveryone]）も名前以外は編集できる（呼び出し側で
  /// 名前欄自体を無効化する）。
  Future<void> updateRole({
    required String groupId,
    required String roleId,
    required String name,
    required int? color,
    required Set<String> permissions,
  });

  /// ロールを削除する（`GroupPermission.manageRoles`が必要）。基準ロールは
  /// 削除できない（呼び出し側で削除ボタン自体を無効化する）。このロールを
  /// 付与されていた全メンバーから外し、広場全体・寄合ごとの優先順位からも除去する。
  /// [requestedBy]は削除実行者本人のuserId（`rooms`サブコレクションの絞り込み
  /// 無し`.get()`が`list`操作としてfirestore.rulesにpermission-deniedされる
  /// 問題を避けるため必要）。
  Future<void> deleteRole({
    required String groupId,
    required String roleId,
    required String requestedBy,
  });

  /// メンバーにロールを1つ付与する（同時に複数付与可、`GroupPermission.
  /// manageRoles`が必要）。
  Future<void> assignRole({
    required String groupId,
    required String userId,
    required String roleId,
  });

  /// メンバーからロールを1つ外す（`GroupPermission.manageRoles`が必要）。
  Future<void> unassignRole({
    required String groupId,
    required String userId,
    required String roleId,
  });

  /// 広場全体でのロール優先順位（呼び名の色を決める順序、先頭が最優先）を
  /// 設定する（`GroupPermission.manageRoles`が必要）。基準ロールは含めない。
  Future<void> setRolePriority({
    required String groupId,
    required List<String> roleIds,
  });

  /// 特定の寄合限定でのロール優先順位の上書きを設定する（[roleIds]がnullなら
  /// 上書きを解除し、広場全体の優先順位に戻す。`GroupPermission.manageRoles`が必要）。
  Future<void> setRoomRolePriorityOverride({
    required String groupId,
    required String roomId,
    required List<String>? roleIds,
  });

  /// 「この寄合独自の設定」トグルを切り替える（`GroupPermission.manageRooms`
  /// が必要）。trueの間、この寄合の`rolePriorityOverride`・
  /// `readReceiptsEnabledOverride`・自分の通知オフ上書きが広場全体の設定より
  /// 優先される（2026-07-29追加）。falseに戻しても、保存済みの上書き値は
  /// 消さずそのまま残す（再度trueにした時に復元されるようにするため）。
  Future<void> setRoomCustomSettingsEnabled({
    required String groupId,
    required String roomId,
    required bool enabled,
  });

  /// 特定の寄合限定での既読機能オン/オフの上書きを設定する（[enabled]が
  /// nullなら上書きを解除し、広場全体の設定に戻す。`GroupPermission.
  /// manageReadReceipts`が必要、`Room.customSettingsEnabled`がtrueの間のみ
  /// 効果を持つ、2026-07-29追加）。オフにする場合は、この寄合の既読履歴を
  /// サーバーから削除する（[setReadReceiptsEnabled]と同じ挙動）。
  Future<void> setRoomReadReceiptsEnabledOverride({
    required String groupId,
    required String roomId,
    required bool? enabled,
  });

  /// 長（オーナー）を別のメンバーに譲渡する（長のみ実行可、firestore.rulesで
  /// 強制）。譲渡後、旧オーナーは通常のメンバーになる。
  Future<void> transferOwnership({
    required String groupId,
    required String newOwnerId,
  });

  /// 広場を丸ごと削除する（長のみ実行可、firestore.rulesで強制）。全ての
  /// 寄合・メッセージ・ロールを物理削除してから広場自体を削除する。他の
  /// 削除系操作（[deleteRoom]等）と同じく猶予期間は設けず、呼び出し側の
  /// 確認ダイアログを経て即時実行する（2026-08-02追加）。参加リクエスト
  /// （`joinRequests`サブコレクション）はfirestore.rulesが物理削除自体を
  /// 常に禁止しているため削除できず残るが、親の広場ドキュメントが消えた
  /// 時点でread権限の判定（`hasGroupPermission`のget()）が失敗しどのみち
  /// 誰からも参照できなくなる。
  Future<void> deleteGroup({
    required String groupId,
    required String requestedBy,
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

  /// ファイル・画像・動画を添付したメッセージを送信する（技術仕様書5.2参照、
  /// 2026-08-10追加）。[contentType]はfile|image|videoのいずれか。
  /// 拡張子ブロックリスト・容量上限（[kMaxAttachmentSizeBytes]）はUI側でも
  /// 事前に弾くが、`uploadMessageAttachment`側でも再検証する。画像は
  /// WebPへの圧縮を試みる（失敗時は元のまま）。
  Future<void> sendAttachmentMessage({
    required String groupId,
    required String roomId,
    required String senderId,
    required String senderRhingId,
    required Uint8List bytes,
    required String fileName,
    required String contentType,
    bool silent = false,
    Message? replyTo,
  });

  /// ペタピタ（スタンプ）を送る。既にStorageにアップロード済みの画像を
  /// 参照するだけなので、[sendAttachmentMessage]と異なりバイトデータの
  /// アップロードを伴わない（技術仕様書7.4参照、2026-08-11追加）。
  Future<void> sendStickerMessage({
    required String groupId,
    required String roomId,
    required String senderId,
    required String senderRhingId,
    required String stickerId,
    required String stickerName,
    required String stickerUrl,
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

  /// 自分のこのメッセージへのリアクションを、呼び出し側が計算済みの
  /// 完全な絵文字リストで上書きする（空リストなら解除。2026-08-05変更、
  /// 以前は単一絵文字の設定/解除だったが、複数の異なる絵文字を同時に
  /// 持てるようになったため、差分ではなく完全なリストを渡す形にした）。
  Future<void> setRoomMessageReaction({
    required String groupId,
    required String roomId,
    required String messageId,
    required String userId,
    required List<String> emojis,
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
  /// [userId]は呼び出し元本人のuserId（`rooms`サブコレクションの絞り込み無し
  /// `.get()`が`list`操作としてfirestore.rulesにpermission-deniedされる問題を
  /// 避けるため、`GroupRepository.watchRooms`と同じ理由で必要）。
  Future<void> setReadReceiptsEnabled({
    required String groupId,
    required bool enabled,
    required String userId,
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
  /// [respondedBy]は応答する本人（長・manageJoinRequests権限保持者）の
  /// userId（`rooms`サブコレクションの絞り込み無し`.get()`が`list`操作として
  /// firestore.rulesにpermission-deniedされる問題を避けるため必要）。
  Future<void> respondToJoinRequest({
    required GroupJoinRequest request,
    required bool accept,
    required String respondedBy,
  });

  /// 広場から退会する。オーナーは退会できない。
  Future<void> leaveGroup({required String groupId, required String userId});
}

class FirestoreGroupRepository implements GroupRepository {
  FirestoreGroupRepository({
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
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
    required bool roomsEnabled,
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
      roomsEnabled: roomsEnabled,
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

    // groupInvites・roles/{everyoneRole}のセキュリティルールはgroups/{groupId}を
    // `get()`で参照してmemberIds/ownerId等を判定するため、groupsのコミット完了後に
    // 別書き込みとして実行する必要がある（同一バッチ内だとget()が未コミットの
    // groupsを見られずpermission-deniedになる）。
    await _groupInvites.doc(groupRef.id).set(invitePreview.toJson());

    // 全メンバーに自動適用される基準ロール（Discordの@everyone相当）。
    // 招待リンク作成はこれまで誰でも可能だったため、その挙動を再現する
    // デフォルト権限にする。色は付けない（他のロールの色を邪魔しないよう、
    // 常に最下位優先度扱いにする、`resolveSenderColor`参照）。
    final everyoneRoleRef = _rolesOf(groupRef.id).doc();
    await everyoneRoleRef.set(
      GroupRole(
        roleId: everyoneRoleRef.id,
        groupId: groupRef.id,
        name: '全員',
        color: null,
        permissions: const {GroupPermission.createInvite},
        isEveryone: true,
      ).toJson(),
    );
    await _recomputeMemberPermissions(groupRef.id);

    return group;
  }

  @override
  Stream<List<Group>> watchGroups(String userId) {
    return _groups
        .where('memberIds', arrayContains: userId)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => Group.fromJson(doc.id, doc.data()))
              .toList(),
        );
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

  @override
  Stream<Group?> watchGroup(String groupId) {
    return _groups
        .doc(groupId)
        .snapshots()
        .map((doc) => doc.exists ? Group.fromJson(doc.id, doc.data()!) : null);
  }

  DocumentReference<Map<String, dynamic>> _roomRef(
    String groupId,
    String roomId,
  ) {
    return _groups.doc(groupId).collection('rooms').doc(roomId);
  }

  @override
  Stream<List<Room>> watchRooms({
    required String groupId,
    required String userId,
  }) {
    // Firestoreの`orderBy`はソート対象フィールドを持たないドキュメントを
    // 結果から除外してしまう。この機能を追加する前に作られた「メイン」室
    // には`createdAt`が無いため、`orderBy('createdAt')`を使うと表示されなく
    // なる不具合があった。クライアント側ソート（`createdAt`が無い場合は
    // 最古扱い）に変更して回避する。
    //
    // where('memberIds', arrayContains: userId)は結果を絞り込むためではなく
    // （この寄合一覧のメンバーは常に広場のメンバーと同一のため実質絞り込み
    // 効果は無い）、firestore.rulesを満たすために必須。`list`操作では
    // クエリ自体にルールと同じ条件のwhere句が無いと、Firestoreは「返り得る
    // 全ドキュメントがルールを満たすと証明できない」として要求全体を
    // permission-deniedで拒否する（各ドキュメントを個別に評価してから
    // 結果をフィルタする、という動作はしない）。これが原因で、この機能を
    // 実装した当初からサイドバーの寄合一覧が一切表示されない不具合があった。
    return _groups
        .doc(groupId)
        .collection('rooms')
        .where('memberIds', arrayContains: userId)
        .snapshots()
        .map((snapshot) {
          final rooms =
              snapshot.docs
                  .map((doc) => Room.fromJson(doc.id, doc.data()))
                  .toList()
                ..sort(_compareByCreatedAt);
          return rooms;
        });
  }

  int _compareByCreatedAt(Room a, Room b) {
    return (a.createdAt?.millisecondsSinceEpoch ?? 0).compareTo(
      b.createdAt?.millisecondsSinceEpoch ?? 0,
    );
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
  Future<void> renameRoom({
    required String groupId,
    required String roomId,
    required String name,
  }) async {
    await _groups.doc(groupId).collection('rooms').doc(roomId).update({
      'name': name,
    });
  }

  @override
  Future<void> setRoomsEnabled({
    required String groupId,
    required bool enabled,
    String? requestedBy,
  }) async {
    if (!enabled) {
      // watchRooms/deleteRoomと同じ理由でwhere句が必須（list操作の
      // firestore.rules要求を満たすため）。
      final roomsSnapshot = await _groups
          .doc(groupId)
          .collection('rooms')
          .where('memberIds', arrayContains: requestedBy)
          .get();
      if (roomsSnapshot.docs.length > 1) {
        throw StateError('寄合が複数あるため単一モードに戻せません');
      }
    }
    await _groups.doc(groupId).update({'roomsEnabled': enabled});
  }

  @override
  Future<void> deleteRoom({
    required String groupId,
    required String roomId,
    required String requestedBy,
  }) async {
    // watchRoomsと同じ理由でorderBy('createdAt')は使わない
    // （createdAtが無い古い「メイン」室が数から漏れてしまうため）。where句は
    // ソートではなくfirestore.rulesの`list`要求を満たすために必須
    // （このwhere句が無いと、rooms=0のpermission-deniedによりこのメソッド
    // 全体が最初のget()で例外を投げ、寄合が削除されないまま残り続けて
    // いた不具合の原因、2026-07-29発覚・修正）。
    final roomsSnapshot = await _groups
        .doc(groupId)
        .collection('rooms')
        .where('memberIds', arrayContains: requestedBy)
        .get();
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
      final remaining = roomsSnapshot.docs.where((d) => d.id != roomId).toList()
        ..sort(
          (a, b) =>
              ((a.data()['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ??
                      0)
                  .compareTo(
                    (b.data()['createdAt'] as Timestamp?)
                            ?.millisecondsSinceEpoch ??
                        0,
                  ),
        );
      if (remaining.isNotEmpty) {
        await _groups.doc(groupId).update({
          'defaultRoomId': remaining.first.id,
        });
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
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => Message.fromJson(doc.id, doc.data()))
              .toList(),
        );
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
      replyToSnippet: replyTo == null
          ? null
          : messageSnippetOf(replyTo.content),
    );

    final batch = _firestore.batch();
    batch.set(messageRef, message.toJson());
    batch.update(roomRef, {'lastMessageAt': FieldValue.serverTimestamp()});
    await batch.commit();
  }

  @override
  Future<void> sendAttachmentMessage({
    required String groupId,
    required String roomId,
    required String senderId,
    required String senderRhingId,
    required Uint8List bytes,
    required String fileName,
    required String contentType,
    bool silent = false,
    Message? replyTo,
  }) async {
    final roomRef = _roomRef(groupId, roomId);
    final messageRef = roomRef.collection('messages').doc();

    final fileMetadata = await uploadMessageAttachment(
      storage: _storage,
      storagePathPrefix: 'groupFiles/$groupId',
      attachmentId: messageRef.id,
      bytes: bytes,
      fileName: fileName,
      contentType: contentType,
    );

    final message = Message(
      messageId: messageRef.id,
      conversationId: roomId,
      conversationType: 'room',
      senderId: senderId,
      senderRhingId: senderRhingId,
      content: fileName,
      contentType: contentType,
      silent: silent,
      replyToMessageId: replyTo?.messageId,
      replyToSenderId: replyTo?.senderId,
      replyToSenderRhingId: replyTo?.senderRhingId,
      replyToSnippet: replyTo == null
          ? null
          : messageSnippetOf(replyTo.content),
      fileMetadata: fileMetadata,
    );

    final batch = _firestore.batch();
    batch.set(messageRef, message.toJson());
    batch.update(roomRef, {'lastMessageAt': FieldValue.serverTimestamp()});
    await batch.commit();
  }

  @override
  Future<void> sendStickerMessage({
    required String groupId,
    required String roomId,
    required String senderId,
    required String senderRhingId,
    required String stickerId,
    required String stickerName,
    required String stickerUrl,
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
      content: stickerName,
      contentType: 'sticker',
      silent: silent,
      replyToMessageId: replyTo?.messageId,
      replyToSenderId: replyTo?.senderId,
      replyToSenderRhingId: replyTo?.senderRhingId,
      replyToSnippet: replyTo == null
          ? null
          : messageSnippetOf(replyTo.content),
      stickerData: MessageStickerData(
        stickerId: stickerId,
        stickerUrl: stickerUrl,
      ),
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
    await _roomRef(
      groupId,
      roomId,
    ).collection('messages').doc(messageId).update({
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
    required List<String> emojis,
  }) async {
    final ref = _roomRef(groupId, roomId).collection('messages').doc(messageId);
    await ref.update({
      'reactions.$userId': emojis.isEmpty ? FieldValue.delete() : emojis,
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
      final chunk = docs.sublist(
        i,
        i + 400 > docs.length ? docs.length : i + 400,
      );
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
    required String userId,
  }) async {
    final group = await getGroup(groupId);
    if (group == null) return;
    await _groups.doc(groupId).update({'readReceiptsEnabled': enabled});
    if (!enabled) {
      // where句はfirestore.rulesの`list`要求を満たすために必須
      // （`deleteRoom`と同じ、2026-07-29追加）。
      final roomsSnapshot = await _groups
          .doc(groupId)
          .collection('rooms')
          .where('memberIds', arrayContains: userId)
          .get();
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
      final format = rawUploadFormatFor(bytes);
      extension = format.extension;
      contentType = format.contentType;
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
      final format = rawUploadFormatFor(bytes);
      extension = format.extension;
      contentType = format.contentType;
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
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => GroupJoinRequest.fromJson(doc.id, doc.data()))
              .toList(),
        );
  }

  @override
  Stream<List<GroupJoinRequest>> watchMyPendingJoinRequests(String userId) {
    return _firestore
        .collectionGroup('joinRequests')
        .where('requesterId', isEqualTo: userId)
        .where('status', isEqualTo: GroupJoinRequestStatus.pending.name)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => GroupJoinRequest.fromJson(doc.id, doc.data()))
              .toList(),
        );
  }

  @override
  Future<void> respondToJoinRequest({
    required GroupJoinRequest request,
    required bool accept,
    required String respondedBy,
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

    // where句はfirestore.rulesの`list`要求を満たすために必須
    // （`deleteRoom`と同じ、2026-07-29追加）。
    final roomsSnapshot = await _groups
        .doc(request.groupId)
        .collection('rooms')
        .where('memberIds', arrayContains: respondedBy)
        .get();

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
    // 新規メンバーにも基準ロールの権限を反映する。
    await _recomputeMemberPermissions(request.groupId);
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
    // where句はfirestore.rulesの`list`要求を満たすために必須
    // （`deleteRoom`と同じ、2026-07-29追加）。退会実行前なので、userIdは
    // まだmemberIdsに含まれている。
    final roomsSnapshot = await _groups
        .doc(groupId)
        .collection('rooms')
        .where('memberIds', arrayContains: userId)
        .get();

    final batch = _firestore.batch();
    batch.update(groupRef, {
      'memberIds': FieldValue.arrayRemove([userId]),
      'memberRoles': updatedRoles,
      'roleAssignments.$userId': FieldValue.delete(),
      'memberPermissions.$userId': FieldValue.delete(),
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
    // watchRoomsと同じ理由でorderBy('createdAt')は使わない（作成直後、
    // サーバー側でserverTimestamp()が解決するまでの一瞬、ローカルの
    // 保留中書き込みがcreatedAt=nullとして扱われ、orderByクエリの結果から
    // 除外されてしまうため）。
    return _rolesOf(groupId).snapshots().map((snapshot) {
      final roles =
          snapshot.docs
              .map((doc) => GroupRole.fromJson(doc.id, doc.data()))
              .toList()
            ..sort(
              (a, b) => (a.createdAt?.millisecondsSinceEpoch ?? 0).compareTo(
                b.createdAt?.millisecondsSinceEpoch ?? 0,
              ),
            );
      return roles;
    });
  }

  @override
  Future<GroupRole> createRole({
    required String groupId,
    required String name,
    required int? color,
    required Set<String> permissions,
  }) async {
    final roleRef = _rolesOf(groupId).doc();
    final role = GroupRole(
      roleId: roleRef.id,
      groupId: groupId,
      name: name,
      color: color,
      permissions: permissions,
    );
    await roleRef.set(role.toJson());
    // 新規ロールを優先順位（色の適用順）の最後尾に追加する。
    await _groups.doc(groupId).update({
      'rolePriority': FieldValue.arrayUnion([roleRef.id]),
    });
    return role;
  }

  @override
  Future<void> updateRole({
    required String groupId,
    required String roleId,
    required String name,
    required int? color,
    required Set<String> permissions,
  }) async {
    await _rolesOf(groupId).doc(roleId).update({
      'name': name,
      'color': color,
      'permissions': permissions.toList(),
    });
    // 権限が変わった可能性があるため、このロールを持つメンバー（基準ロール
    // なら全メンバー）の実効権限を再計算する。
    await _recomputeMemberPermissions(groupId);
  }

  @override
  Future<void> deleteRole({
    required String groupId,
    required String roleId,
    required String requestedBy,
  }) async {
    await _rolesOf(groupId).doc(roleId).delete();

    final groupRef = _groups.doc(groupId);
    final groupDoc = await groupRef.get();
    final group = Group.fromJson(groupRef.id, groupDoc.data()!);

    // このロールを付与されていたメンバーから外し、広場全体の優先順位からも除去する。
    final groupUpdate = <String, dynamic>{
      'rolePriority': FieldValue.arrayRemove([roleId]),
    };
    for (final entry in group.roleAssignments.entries) {
      if (entry.value.contains(roleId)) {
        groupUpdate['roleAssignments.${entry.key}'] = FieldValue.arrayRemove([
          roleId,
        ]);
      }
    }
    await groupRef.update(groupUpdate);

    // 寄合ごとの優先順位上書きからも除去する。where句はfirestore.rulesの
    // `list`要求を満たすために必須（`deleteRoom`と同じ、2026-07-29追加）。
    final roomsSnapshot = await groupRef
        .collection('rooms')
        .where('memberIds', arrayContains: requestedBy)
        .get();
    for (final roomDoc in roomsSnapshot.docs) {
      final override = roomDoc.data()['rolePriorityOverride'];
      if (override is List && override.contains(roleId)) {
        await roomDoc.reference.update({
          'rolePriorityOverride': FieldValue.arrayRemove([roleId]),
        });
      }
    }

    await _recomputeMemberPermissions(groupId);
  }

  @override
  Future<void> assignRole({
    required String groupId,
    required String userId,
    required String roleId,
  }) async {
    await _groups.doc(groupId).update({
      'roleAssignments.$userId': FieldValue.arrayUnion([roleId]),
    });
    await _recomputeMemberPermissions(groupId);
  }

  @override
  Future<void> unassignRole({
    required String groupId,
    required String userId,
    required String roleId,
  }) async {
    await _groups.doc(groupId).update({
      'roleAssignments.$userId': FieldValue.arrayRemove([roleId]),
    });
    await _recomputeMemberPermissions(groupId);
  }

  @override
  Future<void> setRolePriority({
    required String groupId,
    required List<String> roleIds,
  }) async {
    await _groups.doc(groupId).update({'rolePriority': roleIds});
  }

  @override
  Future<void> setRoomRolePriorityOverride({
    required String groupId,
    required String roomId,
    required List<String>? roleIds,
  }) async {
    await _roomRef(groupId, roomId).update({'rolePriorityOverride': roleIds});
  }

  @override
  Future<void> setRoomCustomSettingsEnabled({
    required String groupId,
    required String roomId,
    required bool enabled,
  }) async {
    await _roomRef(groupId, roomId).update({'customSettingsEnabled': enabled});
  }

  @override
  Future<void> setRoomReadReceiptsEnabledOverride({
    required String groupId,
    required String roomId,
    required bool? enabled,
  }) async {
    await _roomRef(
      groupId,
      roomId,
    ).update({'readReceiptsEnabledOverride': enabled});
    if (enabled == false) {
      final messagesRef = _roomRef(groupId, roomId).collection('messages');
      await _clearAllReadReceipts(messagesRef);
    }
  }

  @override
  Future<void> transferOwnership({
    required String groupId,
    required String newOwnerId,
  }) async {
    await _groups.doc(groupId).update({'ownerId': newOwnerId});
  }

  @override
  Future<void> deleteGroup({
    required String groupId,
    required String requestedBy,
  }) async {
    final groupRef = _groups.doc(groupId);
    final groupDoc = await groupRef.get();
    final data = groupDoc.data();
    if (data == null) return;
    final group = Group.fromJson(groupRef.id, data);
    if (group.ownerId != requestedBy) {
      throw StateError('広場の削除は長のみ実行できます');
    }

    // watchRooms/deleteRoomと同じ理由でwhere句が必須（list操作の
    // firestore.rules要求を満たすため）。長は必ず全ての寄合のmemberIdsに
    // 含まれる（createRoomが作成時点のgroup.memberIds全員を登録するため）。
    final roomsSnapshot = await groupRef
        .collection('rooms')
        .where('memberIds', arrayContains: requestedBy)
        .get();
    for (final roomDoc in roomsSnapshot.docs) {
      // deleteRoomと同じ「マーカー→カスケード削除」パターン。このマーカーが
      // 無いとメッセージの物理削除がfirestore.rulesで許可されない。
      await roomDoc.reference.update({'roomDeletionRequestedBy': requestedBy});
      final messagesRef = roomDoc.reference.collection('messages');
      while (true) {
        final snapshot = await messagesRef.limit(400).get();
        if (snapshot.docs.isEmpty) break;
        final batch = _firestore.batch();
        for (final doc in snapshot.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();
      }
      await roomDoc.reference.delete();
    }

    final rolesSnapshot = await _rolesOf(groupId).get();
    if (rolesSnapshot.docs.isNotEmpty) {
      final batch = _firestore.batch();
      for (final doc in rolesSnapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    }

    await groupRef.delete();
  }

  /// [Group.memberPermissions]（userId -> 有効な権限文字列のリスト）を、
  /// 現在のロール定義・付与状況から再計算して書き込む。firestore.rulesが
  /// ロールドキュメントを跨いで動的に権限を判定できないための非正規化
  /// （`Room.memberIds`が`Group.memberIds`を非正規化して持つのと同じ設計）。
  /// 対象人数が小規模な想定のため、常に全メンバー分をまとめて再計算する。
  Future<void> _recomputeMemberPermissions(String groupId) async {
    final groupRef = _groups.doc(groupId);
    final groupDoc = await groupRef.get();
    if (!groupDoc.exists) return;
    final group = Group.fromJson(groupRef.id, groupDoc.data()!);

    final rolesSnapshot = await _rolesOf(groupId).get();
    final roles = rolesSnapshot.docs
        .map((d) => GroupRole.fromJson(d.id, d.data()))
        .toList();
    final rolesById = {for (final role in roles) role.roleId: role};
    final everyoneRole = roles.firstWhereOrNull((r) => r.isEveryone);

    final memberPermissions = <String, List<String>>{
      for (final userId in group.memberIds)
        userId: {
          ...?everyoneRole?.permissions,
          for (final roleId
              in group.roleAssignments[userId] ?? const <String>[])
            ...?rolesById[roleId]?.permissions,
        }.toList(),
    };

    await groupRef.update({'memberPermissions': memberPermissions});
  }
}
