import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_image_compress/flutter_image_compress.dart';

import '../models/app_user.dart';
import '../models/profile_card.dart';
import '../models/profile_material.dart';
import '../models/user_invite_preview.dart';
import '../utils/image_format.dart';

abstract class UserRepository {
  Future<AppUser?> getUser(String userId);

  /// 複数のuserIdからまとめて取得する（広場のメンバー一覧表示などで使う）。
  Future<List<AppUser>> getUsersByIds(List<String> userIds);

  /// 相手のプロフィール（アクティブなニックネームなど）をリアルタイムに購読する。
  Stream<AppUser?> watchUser(String userId);

  Future<void> createUser(AppUser user);
  Future<AppUser?> findByRhingId(String rhingId);
  Future<bool> isRhingIdAvailable(String rhingId);
  Future<void> updateUser(AppUser user);

  /// 蔵の配列フィールド（icons/backgroundImages/statusMessages/nicknames/
  /// profileCards）に1件だけ原子的に追加する。[updateUser]（ローカルで組み立てた
  /// AppUser全体を`.set()`で丸ごと上書き）だと、蔵への追加操作を短時間に
  /// 複数実行した場合（例: アイコンのアップロード中にニックネームを追加するなど）、
  /// 後から完了した書き込みが先に完了した書き込みを消してしまう競合が起きうる。
  /// Firestoreの`arrayUnion`によるフィールド単位の更新はサーバー側でマージされるため、
  /// この種の競合が起きない。
  Future<void> addToProfileList(
    String userId,
    String field,
    Map<String, dynamic> value,
  );

  /// [addToProfileList]の逆（`arrayRemove`）。
  Future<void> removeFromProfileList(
    String userId,
    String field,
    Map<String, dynamic> value,
  );

  /// activeIconId等、単一の値を持つフィールドを原子的に更新する。
  Future<void> setProfileField(String userId, String field, String? value);

  /// 端末をまたいで同期する表示設定（[AppUserPreferences]）を1項目だけ
  /// ドット記法（`preferences.$field`）で部分更新する。他のフィールドや
  /// 未変更の設定項目には影響しない。
  Future<void> updateUserPreference(String userId, String field, Object? value);

  /// 会話（一対のdmId・広場のgroupId）ごとに使うプロフィールカードを設定する
  /// （2026-07-29追加）。[profileCardId]がnullなら上書きを解除し、標準
  /// （[AppUser.activeProfileCardId]）に戻す。
  Future<void> setConversationProfileCard({
    required String userId,
    required String conversationId,
    required String? profileCardId,
  });

  /// プロフィールカードを1件、原子的に保存する（新規作成・既存編集の両方に使う）。
  /// idが一致するカードがあれば置き換え、無ければ追加する。
  ///
  /// [addToProfileList]/[removeFromProfileList]は値そのものの完全一致で
  /// arrayUnion/arrayRemoveするため、カードの編集は「古い値を削除」→
  /// 「新しい値を追加」という2手順が必要だった。この2手順は原子的でない上、
  /// ローカルが把握している「削除すべき古い値」がサーバー上の実データと
  /// 少しでも食い違っていると`arrayRemove`が何もせず素通りしてしまい、
  /// 古いカードが消えないまま新しいカードだけが追加される＝重複が生まれる
  /// 不具合が実際に起きていた。このメソッドはFirestoreのトランザクションで
  /// 保存直前にサーバー上の最新の配列を読み直し、idで置き換えてから書き戻す
  /// ため、ローカルの状態が古くても重複や消し忘れが起きない。
  Future<void> saveProfileCard(String userId, ProfileCard card);

  /// プロフィールカードを1件、原子的に削除する。削除対象が現在の
  /// activeProfileCardIdと一致する場合は、サーバー上の最新の値で判定した上で
  /// それもあわせてクリアする（ローカルの認識が古い場合の取りこぼし防止）。
  Future<void> deleteProfileCard(String userId, String cardId);

  /// 蔵にアイコン画像をアップロードする。Firestoreへの反映は呼び出し側で
  /// [updateUser]を通じて行うこと。
  Future<ProfileMaterial> uploadIcon(String userId, Uint8List bytes);

  /// 蔵に背景画像をアップロードする。Firestoreへの反映は呼び出し側で
  /// [updateUser]を通じて行うこと。
  Future<ProfileMaterial> uploadBackgroundImage(String userId, Uint8List bytes);

  /// アップロード済み画像素材をStorageから削除する。
  Future<void> deleteProfileMaterial(ProfileMaterial material);

  /// 縁結びの招待リンクを外部SNSで展開（OGP）した時に見せる公開プレビュー
  /// （`userInvites/{rhingId}`）を、現在のアクティブなアイコン・呼び名から
  /// 同期する。蔵の更新時（[addToProfileList]等）に自動で呼ばれるほか、
  /// この機能追加より前から使っているユーザーはその同期がまだ一度も
  /// 走っていないため、縁結びページを開いた際にも呼び直してバックフィルする。
  Future<void> syncInvitePreview(String userId);

  /// アカウント削除を申請する。30日間は[restoreAccount]で復元できる。
  /// 何も操作が無いまま31日経過すると、Cloud Functionsの定期処理が
  /// サーバーから全情報を完全削除する。
  Future<void> requestAccountDeletion(String userId);

  /// 削除申請中のアカウントを復元する（31日以内のみ有効）。
  Future<void> restoreAccount(String userId);

  /// アカウントを30日間の復元猶予期間を経ず、今すぐ完全に削除する
  /// （復元不可）。[requestAccountDeletion]と違い、DM/広場への通知・
  /// メンバー除去・friends/friendRequests削除・Firebase Authアカウント削除
  /// までを1回のCloud Functions呼び出し（`deleteAccountImmediately`）で
  /// 完了させる（`functions/src/index.ts`の`deleteAccount`ヘルパーを
  /// 定期処理と共用）。認証中のユーザー自身のみ実行可能。
  Future<void> deleteAccountImmediately();

  /// 認証済みセッションを確認するたびに呼び、最終ログイン日時を更新する
  /// （管理画面向け、2026-08-12追加）。[updateUser]経由にしないのは
  /// [AppUser.lastLoginAt]のドキュメントコメント参照。
  Future<void> touchLastLogin(String userId);

  /// 管理画面向けの住人一覧をリアルタイムに購読する（暫定的に直近500件
  /// まで、2026-08-12追加）。`createdAt`未設定の既存ユーザーも含めて全件
  /// 取得できるよう、Firestore側では並び替えず（`orderBy`はそのフィールドを
  /// 持たないドキュメントを結果から除外してしまうため）、呼び出し側で
  /// 並び替える。
  Stream<List<AppUser>> watchAllUsersForAdmin();

  /// 指定ユーザーのアカウントを停止/解除する（管理者のみ、Cloud Functions
  /// `suspendUserAccount`経由、2026-08-12追加）。
  Future<void> setAccountSuspended(String userId, bool suspended);

  /// 全住人（稼働中のアカウントのみ）に、便りアカウントからの一対メッセージ
  /// としてお知らせを配信する（管理者のみ、Cloud Functions
  /// `broadcastAnnouncement`経由、2026-08-12追加）。
  Future<void> broadcastAnnouncement(String message);

  /// 初回管理者登録（一時的な機能、Cloud Functions `grantFirstAdminOnce`
  /// 経由。既に管理者が存在する場合は失敗する、2026-08-12追加）。
  Future<bool> bootstrapFirstAdmin();

  /// 一度きりの移行処理（一時的な機能、Cloud Functions
  /// `backfillAccountStatusOnce`経由、2026-08-12追加）。`accountStatus`
  /// フィールドが物理的に存在しない古いユーザードキュメントに
  /// `accountStatus: 'active'`をバックフィルする。実行・確認後は
  /// このメソッド・呼び出し元UI・Cloud Function自体を削除する想定
  /// （`bootstrapFirstAdmin`と同じ「使い捨て」の扱い）。
  Future<Map<String, int>> backfillAccountStatusOnce();

  /// Googleカレンダー連携の許可状態を更新する（2026-09-01追加）。
  /// `enabled`がnullなのは初回未確認の状態のみを表し、この呼び出しからは
  /// 使わない（true=許可、false=拒否のどちらかを明示的に書き込む）。
  /// [AppUser.googleCalendarSyncEnabled]参照。
  Future<void> setGoogleCalendarSyncEnabled(String userId, bool enabled);

  /// プッシュ通知の許可状態を更新する（2026-09-01追加、設定タブのトグル用）。
  /// [AppUser.pushNotificationsEnabled]参照。
  Future<void> setPushNotificationsEnabled(String userId, bool enabled);
}

class FirestoreUserRepository implements UserRepository {
  FirestoreUserRepository({
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
    FirebaseFunctions? functions,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _storage = storage ?? FirebaseStorage.instance,
       // Cloud Functions（functions/src/index.ts）はasia-northeast1に
       // デプロイしているため、呼び出し側もリージョンを明示する。
       _functions =
           functions ??
           FirebaseFunctions.instanceFor(region: 'asia-northeast1');

  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;
  final FirebaseFunctions _functions;

  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection('users');

  @override
  Future<AppUser?> getUser(String userId) async {
    final doc = await _users.doc(userId).get();
    if (!doc.exists) return null;
    return AppUser.fromJson(doc.data()!);
  }

  @override
  Future<List<AppUser>> getUsersByIds(List<String> userIds) async {
    if (userIds.isEmpty) return [];
    // FirestoreのwhereInは1クエリにつき最大30件のため、超える場合は分割する。
    final results = <AppUser>[];
    for (var i = 0; i < userIds.length; i += 30) {
      final chunk = userIds.skip(i).take(30).toList();
      final snapshot = await _users
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      results.addAll(snapshot.docs.map((doc) => AppUser.fromJson(doc.data())));
    }
    return results;
  }

  @override
  Stream<AppUser?> watchUser(String userId) {
    return _users
        .doc(userId)
        .snapshots()
        .map((doc) => doc.exists ? AppUser.fromJson(doc.data()!) : null);
  }

  @override
  Future<void> createUser(AppUser user) async {
    // createdAtはtoJson()には含めず、新規作成のこのメソッドでのみサーバー
    // タイムスタンプをマージする（[AppUser.createdAt]のドキュメントコメント
    // 参照。updateUserが同じtoJson()を.set()で全体上書きしているため）。
    await _users.doc(user.userId).set({
      ...user.toJson(),
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> updateUser(AppUser user) async {
    await _users.doc(user.userId).set(user.toJson());
  }

  @override
  Future<void> addToProfileList(
    String userId,
    String field,
    Map<String, dynamic> value,
  ) async {
    await _users.doc(userId).update({
      field: FieldValue.arrayUnion([value]),
    });
    if (_invitePreviewFields.contains(field)) {
      await syncInvitePreview(userId);
    }
  }

  @override
  Future<void> removeFromProfileList(
    String userId,
    String field,
    Map<String, dynamic> value,
  ) async {
    await _users.doc(userId).update({
      field: FieldValue.arrayRemove([value]),
    });
    if (_invitePreviewFields.contains(field)) {
      await syncInvitePreview(userId);
    }
  }

  @override
  Future<void> setProfileField(
    String userId,
    String field,
    String? value,
  ) async {
    await _users.doc(userId).update({field: value});
    if (field == 'activeIconId' ||
        field == 'activeNicknameId' ||
        field == 'activeBackgroundImageId' ||
        field == 'activeStatusMessageId' ||
        field == 'activeProfileCardId') {
      await syncInvitePreview(userId);
    }
  }

  @override
  Future<void> updateUserPreference(
    String userId,
    String field,
    Object? value,
  ) async {
    await _users.doc(userId).update({'preferences.$field': value});
  }

  @override
  Future<void> setConversationProfileCard({
    required String userId,
    required String conversationId,
    required String? profileCardId,
  }) async {
    await _users.doc(userId).update({
      'conversationProfileCardId.$conversationId':
          profileCardId ?? FieldValue.delete(),
    });
  }

  @override
  Future<void> saveProfileCard(String userId, ProfileCard card) async {
    await _firestore.runTransaction((transaction) async {
      final ref = _users.doc(userId);
      final snapshot = await transaction.get(ref);
      final data = snapshot.data();
      final cards = data == null
          ? <ProfileCard>[]
          : AppUser.fromJson(data).profileCards;
      final index = cards.indexWhere((c) => c.id == card.id);
      final updated = [...cards];
      if (index == -1) {
        updated.add(card);
      } else {
        updated[index] = card;
      }
      transaction.update(ref, {
        'profileCards': updated.map((c) => c.toJson()).toList(),
      });
    });
    await syncInvitePreview(userId);
  }

  @override
  Future<void> deleteProfileCard(String userId, String cardId) async {
    await _firestore.runTransaction((transaction) async {
      final ref = _users.doc(userId);
      final snapshot = await transaction.get(ref);
      final data = snapshot.data();
      if (data == null) return;
      final user = AppUser.fromJson(data);
      final remaining = user.profileCards.where((c) => c.id != cardId).toList();
      final updates = <String, dynamic>{
        'profileCards': remaining.map((c) => c.toJson()).toList(),
      };
      if (user.activeProfileCardId == cardId) {
        updates['activeProfileCardId'] = null;
      }
      transaction.update(ref, updates);
    });
    await syncInvitePreview(userId);
  }

  /// 招待プレビュー（[UserInvitePreview]）の内容に影響しうる蔵の配列フィールド。
  /// [addToProfileList]/[removeFromProfileList]がこれらを変更した際は
  /// [syncInvitePreview]で同期し直す（アクティブな工房カードの背景・ステメ・
  /// SNS URLもプレビューに載せるようになったため、アイコン・ニックネームだけで
  /// なくprofileCards自体の変更も対象に含める）。
  static const _invitePreviewFields = {
    'icons',
    'nicknames',
    'backgroundImages',
    'statusMessages',
    'snsLinks',
    'profileCards',
  };

  @override
  Future<void> syncInvitePreview(String userId) async {
    final user = await getUser(userId);
    if (user == null) return;
    final preview = UserInvitePreview(
      userId: user.userId,
      nickname: user.effectiveNickname?.text,
      iconUrl: user.effectiveIcon?.url,
      statusMessage: user.effectiveStatusMessage?.text,
      backgroundImageUrl: user.effectiveBackgroundImage?.url,
      snsLinkUrls: [for (final link in user.effectiveSnsLinks) link.url],
    );
    await _firestore
        .collection('userInvites')
        .doc(user.rhingId)
        .set(preview.toJson());
  }

  @override
  Future<AppUser?> findByRhingId(String rhingId) async {
    final snapshot = await _users
        .where('rhingId', isEqualTo: rhingId.toLowerCase())
        .limit(1)
        .get();
    if (snapshot.docs.isEmpty) return null;
    return AppUser.fromJson(snapshot.docs.first.data());
  }

  @override
  Future<bool> isRhingIdAvailable(String rhingId) async {
    final snapshot = await _users
        .where('rhingId', isEqualTo: rhingId.toLowerCase())
        .limit(1)
        .get();
    return snapshot.docs.isEmpty;
  }

  @override
  Future<ProfileMaterial> uploadIcon(String userId, Uint8List bytes) {
    return _uploadMaterial(userId: userId, folder: 'icons', bytes: bytes);
  }

  @override
  Future<ProfileMaterial> uploadBackgroundImage(
    String userId,
    Uint8List bytes,
  ) {
    return _uploadMaterial(
      userId: userId,
      folder: 'backgroundImages',
      bytes: bytes,
    );
  }

  Future<ProfileMaterial> _uploadMaterial({
    required String userId,
    required String folder,
    required Uint8List bytes,
  }) async {
    final id = _users.doc().id;
    // image_pickerはリサイズ・圧縮をせず、カメラ由来の数MB〜10MB超の生バイトを
    // そのまま返すことがある。蔵のサムネイルは72〜128px程度でしか表示しない上、
    // 巨大なJPEGのままだと読み込みが極端に遅く「真っ白」に見える一因になっていた
    // ため、WebPへの圧縮・リサイズを行う（CLAUDE.md記載の画像圧縮方針）。
    // flutter_image_compressはWindows/Linuxを未対応のため、その場合や
    // 何らかの理由で圧縮に失敗した場合は元のバイトのままアップロードする
    // （圧縮失敗でアップロード自体をブロックしないためのフォールバック）。
    // GIFはWebPに圧縮するとアニメーションが失われ1コマの静止画になって
    // しまうため、圧縮自体をスキップして元のバイトのままアップロードする。
    final isGif = isGifBytes(bytes);
    final compressed = isGif
        ? null
        : await _tryCompressToWebp(bytes, folder: folder);
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
    final path = 'profileMaterials/$userId/$folder/$id.$extension';
    final ref = _storage.ref(path);
    await ref.putData(
      compressed ?? bytes,
      SettableMetadata(contentType: contentType),
    );
    final url = await ref.getDownloadURL();
    return ProfileMaterial(id: id, url: url, storagePath: path);
  }

  Future<Uint8List?> _tryCompressToWebp(
    Uint8List bytes, {
    required String folder,
  }) async {
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) return null;
    final isIcon = folder == 'icons';
    try {
      return await FlutterImageCompress.compressWithList(
        bytes,
        minWidth: isIcon ? 512 : 1080,
        minHeight: isIcon ? 512 : 1080,
        quality: isIcon ? 85 : 80,
        format: CompressFormat.webp,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> deleteProfileMaterial(ProfileMaterial material) async {
    await _storage.ref(material.storagePath).delete();
  }

  @override
  Future<void> requestAccountDeletion(String userId) async {
    await _users.doc(userId).update({
      'accountStatus': AccountStatus.pendingDeletion.name,
      'deletionRequestedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> restoreAccount(String userId) async {
    await _users.doc(userId).update({
      'accountStatus': AccountStatus.active.name,
      'deletionRequestedAt': null,
    });
  }

  @override
  Future<void> deleteAccountImmediately() async {
    await _functions.httpsCallable('deleteAccountImmediately').call();
  }

  @override
  Future<void> touchLastLogin(String userId) async {
    await _users.doc(userId).update({
      'lastLoginAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Stream<List<AppUser>> watchAllUsersForAdmin() {
    return _users
        .limit(500)
        .snapshots()
        .map(
          (snap) =>
              snap.docs.map((doc) => AppUser.fromJson(doc.data())).toList(),
        );
  }

  @override
  Future<void> setAccountSuspended(String userId, bool suspended) async {
    await _functions.httpsCallable('suspendUserAccount').call({
      'targetUserId': userId,
      'suspend': suspended,
    });
  }

  @override
  Future<void> broadcastAnnouncement(String message) async {
    await _functions.httpsCallable('broadcastAnnouncement').call({
      'message': message,
    });
  }

  @override
  Future<bool> bootstrapFirstAdmin() async {
    final result = await _functions.httpsCallable('grantFirstAdminOnce').call();
    return result.data['granted'] == true;
  }

  @override
  Future<Map<String, int>> backfillAccountStatusOnce() async {
    final result = await _functions
        .httpsCallable('backfillAccountStatusOnce')
        .call();
    final data = Map<String, dynamic>.from(result.data as Map);
    return {
      'scanned': data['scanned'] as int,
      'backfilled': data['backfilled'] as int,
    };
  }

  @override
  Future<void> setGoogleCalendarSyncEnabled(String userId, bool enabled) {
    return _users.doc(userId).update({'googleCalendarSyncEnabled': enabled});
  }

  @override
  Future<void> setPushNotificationsEnabled(String userId, bool enabled) {
    return _users.doc(userId).update({'pushNotificationsEnabled': enabled});
  }
}
