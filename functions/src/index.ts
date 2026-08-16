import { initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import {
  FieldValue,
  getFirestore,
  Timestamp,
  type WriteBatch,
} from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";
import { logger } from "firebase-functions";
import { defineSecret } from "firebase-functions/params";
import { onDocumentWritten } from "firebase-functions/v2/firestore";
import { HttpsError, onCall, onRequest } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import Stripe from "stripe";

initializeApp();

const db = getFirestore();

// Stripe連携用のシークレット（値はFirebase CLIの
// `firebase functions:secrets:set STRIPE_SECRET_KEY` 等で個別に設定する。
// コード上には値を持たない）。
const stripeSecretKey = defineSecret("STRIPE_SECRET_KEY");
const stripeWebhookSecret = defineSecret("STRIPE_WEBHOOK_SECRET");

let stripeClient: Stripe | null = null;
function getStripeClient(): Stripe {
  if (!stripeClient) {
    stripeClient = new Stripe(stripeSecretKey.value());
  }
  return stripeClient;
}

const DELETION_GRACE_PERIOD_DAYS = 31;
const ACCOUNT_DELETED_NOTICE_CONTENT = "アカウントを削除しました";
const BATCH_LIMIT = 400;

/**
 * 500件までのバッチ上限を超えないよう、操作数に応じて自動的に
 * バッチをコミットし直しながら書き込みを蓄積するヘルパー。
 */
class ChunkedWriter {
  private batch: WriteBatch = db.batch();
  private count = 0;

  private async flushIfNeeded(): Promise<void> {
    this.count += 1;
    if (this.count >= BATCH_LIMIT) {
      await this.batch.commit();
      this.batch = db.batch();
      this.count = 0;
    }
  }

  async set(
    ref: FirebaseFirestore.DocumentReference,
    data: FirebaseFirestore.DocumentData,
  ): Promise<void> {
    this.batch.set(ref, data);
    await this.flushIfNeeded();
  }

  async update(
    ref: FirebaseFirestore.DocumentReference,
    data: FirebaseFirestore.DocumentData,
  ): Promise<void> {
    this.batch.update(ref, data);
    await this.flushIfNeeded();
  }

  async delete(ref: FirebaseFirestore.DocumentReference): Promise<void> {
    this.batch.delete(ref);
    await this.flushIfNeeded();
  }

  async commit(): Promise<void> {
    if (this.count > 0) {
      await this.batch.commit();
      this.batch = db.batch();
      this.count = 0;
    }
  }
}

/**
 * アカウント削除から31日が経過した（＝復元されなかった）ユーザーを
 * 毎日00:00（Asia/Tokyo）に検出し、サーバーから全情報を完全削除する。
 * DaiDai/CLAUDE.md「重要な仕様・制約」参照。
 */
export const processAccountDeletions = onSchedule(
  { schedule: "0 0 * * *", timeZone: "Asia/Tokyo", region: "asia-northeast1" },
  async () => {
    const cutoff = Timestamp.fromMillis(
      Date.now() - DELETION_GRACE_PERIOD_DAYS * 24 * 60 * 60 * 1000,
    );
    const snapshot = await db
      .collection("users")
      .where("accountStatus", "==", "pendingDeletion")
      .where("deletionRequestedAt", "<=", cutoff)
      .get();

    if (snapshot.empty) return;

    for (const doc of snapshot.docs) {
      try {
        // 長を務める広場が残っている間は削除できない（クライアント側の
        // アカウント削除画面が事前に譲渡を求めるが、30日の猶予期間中に
        // 新たに広場を作成・譲受した場合もあり得るため、実行直前にも
        // 再チェックする）。残っていればスキップし、翌日以降に再試行する。
        if (await hasOwnedGroups(doc.id)) {
          logger.warn(
            `アカウント削除を保留（長を務める広場が残っています）: ${doc.id}`,
          );
          continue;
        }
        await deleteAccount(doc.id, doc.data());
        logger.info(`アカウント削除完了: ${doc.id}`);
      } catch (error) {
        // 1ユーザーの処理失敗が他のユーザーの処理を止めないようにする。
        // 失敗したユーザーはaccountStatusがpendingDeletionのまま残るため、
        // 翌日の実行で再試行される。
        logger.error(`アカウント削除に失敗: ${doc.id}`, error);
      }
    }
  },
);

/** [userId]が長（`Group.ownerId`）を務めている広場が1件でもあるか。
 * アカウント削除は全ての広場で長を譲渡し終えるまで実行できない
 * （DaiDai/CLAUDE.md「重要な仕様・制約」参照、2026-08-02追加）。 */
async function hasOwnedGroups(userId: string): Promise<boolean> {
  const snapshot = await db
    .collection("groups")
    .where("ownerId", "==", userId)
    .limit(1)
    .get();
  return !snapshot.empty;
}

/**
 * 30日間の復元猶予期間を経ず、呼び出したユーザー自身のアカウントを今すぐ
 * 完全に削除する（復元不可）。DM/広場への通知・メンバー除去・
 * friends/friendRequests削除等は[processAccountDeletions]と全く同じ
 * [deleteAccount]ヘルパーを共用する。[request.auth.uid]以外のユーザーを
 * 削除することはできない（他人のアカウントを消せないようにするため）。
 */
export const deleteAccountImmediately = onCall(
  { region: "asia-northeast1" },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }
    const userDoc = await db.collection("users").doc(uid).get();
    if (!userDoc.exists) {
      throw new HttpsError("not-found", "ユーザーが見つかりません");
    }
    // クライアント側（設定＞アカウント）が削除操作の前に長を務める広場の
    // 譲渡を求めるが、直接この関数を呼び出すことでバイパスされうるため
    // サーバー側でも同じ制約を強制する（2026-08-02追加）。
    if (await hasOwnedGroups(uid)) {
      throw new HttpsError(
        "failed-precondition",
        "長を務めている広場があります。先に長を譲渡してください",
      );
    }
    await deleteAccount(uid, userDoc.data()!);
    logger.info(`アカウント即時削除完了: ${uid}`);
  },
);

async function deleteAccount(
  userId: string,
  userData: FirebaseFirestore.DocumentData,
): Promise<void> {
  const rhingId: string | undefined = userData.rhingId;
  const writer = new ChunkedWriter();

  await notifyDirectMessages(userId, rhingId, writer);
  await notifyAndLeaveGroups(userId, rhingId, writer);
  await deleteFriends(userId, writer);
  await deleteFriendRequests(userId, writer);

  if (rhingId) {
    await writer.delete(db.collection("userInvites").doc(rhingId));
  }
  // daidai横丁で出品者だった場合のみ存在する公開プロフィールミラー
  // （creatorProfiles、非出品者には存在しないが、無条件のdeleteは安全）。
  await writer.delete(db.collection("creatorProfiles").doc(userId));
  await deleteSubcollection(
    db.collection("users").doc(userId).collection("conversationPrefs"),
    writer,
  );
  await deleteSubcollection(
    db.collection("users").doc(userId).collection("blockedUsers"),
    writer,
  );
  await writer.delete(db.collection("users").doc(userId));
  await writer.commit();

  await getAuth().deleteUser(userId).catch((error) => {
    // Firebase Auth側に既にユーザーが存在しない場合等は無視する
    // （Firestore側のクリーンアップは既に完了しているため）。
    logger.warn(`Firebase Authユーザーの削除に失敗: ${userId}`, error);
  });
}

/** 参加中の一対それぞれに、アカウント削除通知メッセージを1件追加する。
 * この一対の既定の寄合（defaultRoomId）に投稿する（どの寄合を開いていても
 * 内容が分かるようにするため）。メッセージ・寄合・DMドキュメント自体は
 * ここでは削除しない（もう一方の参加者がチャット画面で「はい」を選んだ
 * 場合のみクライアント側で物理削除される。
 * DirectMessageRepository.deleteDmAfterAccountDeletion参照）。 */
async function notifyDirectMessages(
  userId: string,
  rhingId: string | undefined,
  writer: ChunkedWriter,
): Promise<void> {
  const dms = await db
    .collection("directMessages")
    .where("participants", "array-contains", userId)
    .get();

  for (const dm of dms.docs) {
    const defaultRoomId: string | undefined = dm.data().defaultRoomId;
    if (!defaultRoomId) continue;

    const roomRef = dm.ref.collection("rooms").doc(defaultRoomId);
    const messageRef = roomRef.collection("messages").doc();
    await writer.set(messageRef, {
      conversationId: defaultRoomId,
      conversationType: "dm",
      senderId: userId,
      senderRhingId: rhingId ?? null,
      content: ACCOUNT_DELETED_NOTICE_CONTENT,
      contentType: "accountDeleted",
      sentAt: FieldValue.serverTimestamp(),
      hiddenFor: [],
      readBy: [],
      isSpam: false,
      silent: false,
      reactions: {},
      accountDeletionResponse: null,
    });
    await writer.update(roomRef, {
      lastMessageAt: FieldValue.serverTimestamp(),
    });
    await writer.update(dm.ref, {
      accountDeletedUserId: userId,
      lastMessageAt: FieldValue.serverTimestamp(),
    });
  }
}

/** 参加中の広場それぞれに、アカウント削除通知メッセージを1件追加する
 * （広場側は通知のみで、削除するかどうかの選択肢は無い）。長でない場合は
 * memberIds/memberRolesから除去する（group_repository.dartのleaveGroupと
 * 同じ操作）。呼び出し時点で長を務める広場は無いはず（[deleteAccount]の
 * 呼び出し元が事前に[hasOwnedGroups]で弾いているため）だが、念のため
 * 長のままの場合は除去せず通知のみ行う防御的分岐を残す。 */
async function notifyAndLeaveGroups(
  userId: string,
  rhingId: string | undefined,
  writer: ChunkedWriter,
): Promise<void> {
  const groups = await db
    .collection("groups")
    .where("memberIds", "array-contains", userId)
    .get();

  for (const group of groups.docs) {
    const groupData = group.data();
    const defaultRoomId: string | undefined = groupData.defaultRoomId;
    if (!defaultRoomId) continue;

    const roomRef = group.ref.collection("rooms").doc(defaultRoomId);
    const messageRef = roomRef.collection("messages").doc();
    await writer.set(messageRef, {
      conversationId: defaultRoomId,
      conversationType: "room",
      senderId: userId,
      senderRhingId: rhingId ?? null,
      content: ACCOUNT_DELETED_NOTICE_CONTENT,
      contentType: "accountDeleted",
      sentAt: FieldValue.serverTimestamp(),
      hiddenFor: [],
      readBy: [],
      isSpam: false,
      silent: false,
      reactions: {},
    });

    if (groupData.ownerId !== userId) {
      const memberRoles = { ...(groupData.memberRoles ?? {}) };
      delete memberRoles[userId];
      await writer.update(group.ref, {
        memberIds: FieldValue.arrayRemove(userId),
        memberRoles,
      });
      await writer.update(roomRef, {
        memberIds: FieldValue.arrayRemove(userId),
      });
    }
  }
}

async function deleteFriends(
  userId: string,
  writer: ChunkedWriter,
): Promise<void> {
  const friends = await db
    .collection("users")
    .doc(userId)
    .collection("friends")
    .get();

  for (const friend of friends.docs) {
    await writer.delete(friend.ref);
    await writer.delete(
      db.collection("users").doc(friend.id).collection("friends").doc(userId),
    );
  }
}

async function deleteFriendRequests(
  userId: string,
  writer: ChunkedWriter,
): Promise<void> {
  const [asFrom, asTo] = await Promise.all([
    db.collection("friendRequests").where("fromUserId", "==", userId).get(),
    db.collection("friendRequests").where("toUserId", "==", userId).get(),
  ]);
  for (const doc of [...asFrom.docs, ...asTo.docs]) {
    await writer.delete(doc.ref);
  }
}

async function deleteSubcollection(
  collectionRef: FirebaseFirestore.CollectionReference,
  writer: ChunkedWriter,
): Promise<void> {
  const snapshot = await collectionRef.get();
  for (const doc of snapshot.docs) {
    await writer.delete(doc.ref);
  }
}

const QR_LOGIN_SESSION_TTL_MS = 3 * 60 * 1000;

/**
 * QRコードによるログイン（2026-08-09実装）。未ログイン端末が
 * `qrLoginSessions/{sessionId}`にpendingなセッションを作成してQRコードを表示し、
 * ログイン済みの別端末がアプリ内スキャナーで読み取って承認する（LINE PC版/
 * WhatsApp Webと同じ方式）。カスタムトークンはFirestoreに一切書き込まず
 * claimQrLoginSessionのレスポンスとしてのみ返すため、セッションIDが漏れても
 * トークン自体は盗めない設計（DaiDai/CLAUDE.md参照）。
 */

/** ログイン済み端末（`lib/features/settings/settings_tab.dart`の`_QrLoginRow`）が呼ぶ。 */
export const approveQrLoginSession = onCall(
  { region: "asia-northeast1" },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }
    const sessionId = request.data?.sessionId;
    if (typeof sessionId !== "string" || !sessionId) {
      throw new HttpsError("invalid-argument", "sessionIdが必要です");
    }
    const ref = db.collection("qrLoginSessions").doc(sessionId);
    const doc = await ref.get();
    if (!doc.exists) {
      throw new HttpsError("not-found", "セッションが見つかりません");
    }
    const data = doc.data()!;
    if (data.status !== "pending") {
      throw new HttpsError(
        "failed-precondition",
        "このQRコードは既に使用されているか無効です",
      );
    }
    const createdAt = data.createdAt as Timestamp | undefined;
    if (
      !createdAt ||
      Date.now() - createdAt.toMillis() > QR_LOGIN_SESSION_TTL_MS
    ) {
      throw new HttpsError("deadline-exceeded", "QRコードの有効期限が切れています");
    }
    await ref.update({ status: "approved", approvedUid: uid });
  },
);

/**
 * 未ログイン端末（`lib/features/auth/qr_login_dialog.dart`）が、承認済みに
 * なったセッションを検知したら呼ぶ。カスタムトークンを発行して返す。
 */
export const claimQrLoginSession = onCall(
  { region: "asia-northeast1" },
  async (request) => {
    const sessionId = request.data?.sessionId;
    if (typeof sessionId !== "string" || !sessionId) {
      throw new HttpsError("invalid-argument", "sessionIdが必要です");
    }
    const ref = db.collection("qrLoginSessions").doc(sessionId);
    const customToken = await db.runTransaction(async (tx) => {
      const doc = await tx.get(ref);
      if (!doc.exists) {
        throw new HttpsError("not-found", "セッションが見つかりません");
      }
      const data = doc.data()!;
      if (data.status !== "approved") {
        throw new HttpsError("failed-precondition", "まだ承認されていません");
      }
      const createdAt = data.createdAt as Timestamp | undefined;
      if (
        !createdAt ||
        Date.now() - createdAt.toMillis() > QR_LOGIN_SESSION_TTL_MS
      ) {
        throw new HttpsError("deadline-exceeded", "QRコードの有効期限が切れています");
      }
      tx.update(ref, { status: "claimed" });
      // createCustomTokenはローカルなJWT署名処理でネットワークI/Oを伴わないため、
      // トランザクションのリトライ内で呼んでも副作用が重複しない。
      return getAuth().createCustomToken(data.approvedUid as string);
    });
    return { customToken };
  },
);

/**
 * 期限切れの`qrLoginSessions`を定期的に掃除する（1時間ごと）。各Functionが
 * 都度期限を検証するためセキュリティ上必須ではないが、Firestoreにゴミが
 * 溜まらないようにする衛生用ジョブ。
 */
export const cleanupQrLoginSessions = onSchedule(
  { schedule: "every 60 minutes", region: "asia-northeast1" },
  async () => {
    const cutoff = Timestamp.fromMillis(Date.now() - QR_LOGIN_SESSION_TTL_MS);
    const snapshot = await db
      .collection("qrLoginSessions")
      .where("createdAt", "<", cutoff)
      .get();
    const writer = new ChunkedWriter();
    for (const doc of snapshot.docs) {
      await writer.delete(doc.ref);
    }
    await writer.commit();
  },
);

// ---------------------------------------------------------------------
// daidai横丁: ペタピタパッケージ関連のcallable（技術仕様書7.4・7.5参照、
// 2026-08-11追加）。stickerPacks/stickerPackReportsはfirestore.rulesで
// クライアントからの書き込みを一律禁止しているため、パックの作成・編集・
// 通報はすべてここを経由する。HomePage-Rhing（daidai-yokochoセクション）
// からFirebase Client SDKのhttpsCallableで呼ばれる想定。
// ---------------------------------------------------------------------

const MIN_STICKERS_PER_PACK = 4;

// 有料パックの出品・価格変更・購入を一時的に無効化するフラグ（2026-08-11追加）。
// 特定商取引法に基づく表記の整備・出品者への収益分配方式の決定・Stripe本番
// アカウントの審査が完了するまでは、無料（price===0）パックの配布のみに限定する。
// 再開条件・チェックリストはDaiDai-技術仕様書.md 7.6節を参照。再開時はこの値を
// trueに変更するだけでよい（Stripe連携コード自体は動作確認済みのため削除しない）。
const PAID_PACKS_ENABLED = false;
const PAID_PACKS_DISABLED_MESSAGE =
  "現在、有料パックには対応していません。無料（0円）パックのみご利用いただけます。";

interface StickerInput {
  stickerId: string;
  name: string;
  imageUrl: string;
}

/** stickersフィールドの形式（配列・各要素のstickerId/name/imageUrl）を検証する。 */
function assertValidStickers(value: unknown, minCount: number): StickerInput[] {
  if (!Array.isArray(value) || value.length < minCount) {
    throw new HttpsError(
      "invalid-argument",
      `stickersは${minCount}件以上の配列が必要です`,
    );
  }
  return value.map((item, index) => {
    const s = item as Partial<StickerInput> | null;
    if (
      typeof s !== "object" ||
      s === null ||
      typeof s.stickerId !== "string" || !s.stickerId ||
      typeof s.name !== "string" || !s.name ||
      typeof s.imageUrl !== "string" || !s.imageUrl
    ) {
      throw new HttpsError(
        "invalid-argument",
        `stickers[${index}]の形式が不正です（stickerId/name/imageUrlの文字列が必要）`,
      );
    }
    return { stickerId: s.stickerId, name: s.name, imageUrl: s.imageUrl };
  });
}

function assertValidPrice(value: unknown): number {
  if (typeof value !== "number" || !Number.isInteger(value) || value < 0) {
    throw new HttpsError("invalid-argument", "priceは0以上の整数が必要です");
  }
  return value;
}

/**
 * `users/{uid}`ドキュメントから、daidai横丁で公開してよい最小限の
 * クリエイター情報を算出する。「工房カード」(profileCards)ごとの
 * 呼び名/アイコン切り替えは再現せず、蔵のアクティブ素材（activeNicknameId/
 * activeIconId/activeStatusMessageId）のみを見る簡易実装（v1方針）。
 */
function buildCreatorProfileFields(
  userData: FirebaseFirestore.DocumentData,
): FirebaseFirestore.DocumentData {
  const nicknames = Array.isArray(userData.nicknames) ? userData.nicknames : [];
  const icons = Array.isArray(userData.icons) ? userData.icons : [];
  const statusMessages = Array.isArray(userData.statusMessages)
    ? userData.statusMessages
    : [];
  const snsLinks = Array.isArray(userData.snsLinks) ? userData.snsLinks : [];

  const activeNickname = nicknames.find(
    (n: { id?: unknown }) => n?.id === userData.activeNicknameId,
  );
  const activeIcon = icons.find(
    (i: { id?: unknown }) => i?.id === userData.activeIconId,
  );
  const activeStatusMessage = statusMessages.find(
    (s: { id?: unknown }) => s?.id === userData.activeStatusMessageId,
  );

  // daidai横丁専用の呼び名・アイコン（2026-08-16追加、users/{uid}.daidaiNickname/
  // daidaiIconUrl）はDaiDai本体の身だしなみとは独立した任意設定で、設定されて
  // いればそちらを優先し、無ければ従来通りDaiDaiのアクティブ素材にフォールバックする。
  const daidaiNickname = typeof userData.daidaiNickname === "string" ? userData.daidaiNickname : null;
  const daidaiIconUrl = typeof userData.daidaiIconUrl === "string" ? userData.daidaiIconUrl : null;

  return {
    rhingId: typeof userData.rhingId === "string" ? userData.rhingId : "",
    nickname: daidaiNickname ?? (typeof activeNickname?.text === "string" ? activeNickname.text : null),
    iconUrl: daidaiIconUrl ?? (typeof activeIcon?.url === "string" ? activeIcon.url : null),
    // 専用の自己紹介フィールドが無いため、ステメ（最大40字）を流用する。
    statusMessage:
      typeof activeStatusMessage?.text === "string" ? activeStatusMessage.text : null,
    snsLinkUrls: snsLinks
      .map((s: { url?: unknown }) => s?.url)
      .filter((url: unknown): url is string => typeof url === "string"),
    updatedAt: FieldValue.serverTimestamp(),
  };
}

/**
 * `creatorProfiles/{userId}`（daidai横丁の公開プロフィールミラー、
 * read:true/write:falseでクライアントからは読み取り専用）をmerge更新する。
 * `createStickerPack`の初回作成と、`syncCreatorProfile`トリガーの両方から呼ぶ。
 */
async function projectCreatorProfile(
  userId: string,
  userData: FirebaseFirestore.DocumentData,
): Promise<void> {
  await db
    .collection("creatorProfiles")
    .doc(userId)
    .set(buildCreatorProfileFields(userData), { merge: true });
}

/**
 * 出品者（DaiDaiアカウントを持つ誰でも即出品可、承認フローなし）が新規パックを
 * 作成する。creatorIdは呼び出し元のuidで固定し、他人になりすませないようにする。
 */
export const createStickerPack = onCall(
  { region: "asia-northeast1" },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }
    const name = request.data?.name;
    if (typeof name !== "string" || !name.trim()) {
      throw new HttpsError("invalid-argument", "nameが必要です");
    }
    const price = assertValidPrice(request.data?.price);
    if (price > 0 && !PAID_PACKS_ENABLED) {
      throw new HttpsError("failed-precondition", PAID_PACKS_DISABLED_MESSAGE);
    }
    const stickers = assertValidStickers(request.data?.stickers, MIN_STICKERS_PER_PACK);
    const category = typeof request.data?.category === "string" ? request.data.category : "";
    const tags: string[] = Array.isArray(request.data?.tags)
      ? request.data.tags.filter((t: unknown): t is string => typeof t === "string")
      : [];

    const ref = db.collection("stickerPacks").doc();
    await ref.set({
      creatorId: uid,
      name: name.trim(),
      price,
      stickers,
      category,
      tags,
      salesCount: 0,
      // 現在このパックを所有しているユーザー数（購入付与Cloud Functionで+1、
      // アンインストール時のownedStickerPacks削除に連動して-1する想定の
      // 非正規化カウンタ、2026-08-11追加）。deleteStickerPackの削除可否判定に使う。
      // 購入付与・アンインストール連動の実処理はまだ未実装のため、現時点では
      // 常に0のまま（＝どのパックも削除可能）。
      ownerCount: 0,
      createdAt: FieldValue.serverTimestamp(),
    });

    // 初出品のタイミングで、daidai横丁の公開プロフィールミラー
    // （creatorProfiles）を初回作成する。以後の呼び名/アイコン変更は
    // syncCreatorProfileトリガーが追随する。
    const userDoc = await db.collection("users").doc(uid).get();
    if (userDoc.exists) {
      await projectCreatorProfile(uid, userDoc.data()!);
    }

    return { packId: ref.id };
  },
);

/**
 * 出品済みパックのname・priceのみを変更する。画像（stickers）はここでは
 * 変更できない（追加専用の方針、addStickersToStickerPack参照）。
 */
export const updateStickerPackMeta = onCall(
  { region: "asia-northeast1" },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }
    const packId = request.data?.packId;
    if (typeof packId !== "string" || !packId) {
      throw new HttpsError("invalid-argument", "packIdが必要です");
    }
    const ref = db.collection("stickerPacks").doc(packId);
    const doc = await ref.get();
    if (!doc.exists) {
      throw new HttpsError("not-found", "パックが見つかりません");
    }
    if (doc.data()?.creatorId !== uid) {
      throw new HttpsError("permission-denied", "自分が出品したパックのみ編集できます");
    }

    const update: { name?: string; price?: number; updatedAt?: FirebaseFirestore.FieldValue } = {};
    if (request.data?.name !== undefined) {
      if (typeof request.data.name !== "string" || !request.data.name.trim()) {
        throw new HttpsError("invalid-argument", "nameが不正です");
      }
      update.name = request.data.name.trim();
    }
    if (request.data?.price !== undefined) {
      const newPrice = assertValidPrice(request.data.price);
      const currentPrice = typeof doc.data()?.price === "number" ? doc.data()!.price : 0;
      // 既に有料設定済みのパック（凍結前に作成されたもの）の価格を維持する
      // 更新までは塞がない。新たに有料へ変更する操作のみを拒否する。
      if (newPrice > 0 && newPrice !== currentPrice && !PAID_PACKS_ENABLED) {
        throw new HttpsError("failed-precondition", PAID_PACKS_DISABLED_MESSAGE);
      }
      update.price = newPrice;
    }
    if (Object.keys(update).length === 0) {
      throw new HttpsError("invalid-argument", "name・priceのいずれかが必要です");
    }
    update.updatedAt = FieldValue.serverTimestamp();
    await ref.update(update);
  },
);

/**
 * 出品済みパックに画像を追加する。技術仕様書7.5節の方針により追加専用
 * （削除・差し替えは不可、購入済みユーザーの手持ちスタンプを変えないため）。
 */
export const addStickersToStickerPack = onCall(
  { region: "asia-northeast1" },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }
    const packId = request.data?.packId;
    if (typeof packId !== "string" || !packId) {
      throw new HttpsError("invalid-argument", "packIdが必要です");
    }
    // パック全体の下限4件はcreateStickerPack側で保証済みのため、
    // 追加時は1件以上あればよい。
    const stickers = assertValidStickers(request.data?.stickers, 1);

    const ref = db.collection("stickerPacks").doc(packId);
    const doc = await ref.get();
    if (!doc.exists) {
      throw new HttpsError("not-found", "パックが見つかりません");
    }
    if (doc.data()?.creatorId !== uid) {
      throw new HttpsError("permission-denied", "自分が出品したパックのみ編集できます");
    }
    const existingIds = new Set(
      ((doc.data()?.stickers as StickerInput[] | undefined) ?? []).map((s) => s.stickerId),
    );
    for (const s of stickers) {
      if (existingIds.has(s.stickerId)) {
        throw new HttpsError("invalid-argument", `stickerId "${s.stickerId}" は既に存在します`);
      }
    }
    await ref.update({
      stickers: FieldValue.arrayUnion(...stickers),
      updatedAt: FieldValue.serverTimestamp(),
    });
  },
);

/**
 * `users/{userId}`が書き込まれるたびに、既に`creatorProfiles/{userId}`
 * （=出品経験のあるユーザー）が存在する場合のみ公開プロフィールを
 * 同期する。非出品者への無駄な書き込みを避けるため、存在しない場合は
 * 何もしない（新規作成は`createStickerPack`側の責務）。
 */
export const syncCreatorProfile = onDocumentWritten(
  { document: "users/{userId}", region: "asia-northeast1" },
  async (event) => {
    const after = event.data?.after;
    if (!after || !after.exists) return; // 削除はdeleteAccount側で処理する
    const profileRef = db.collection("creatorProfiles").doc(event.params.userId);
    const existing = await profileRef.get();
    if (!existing.exists) return;
    await projectCreatorProfile(event.params.userId, after.data()!);
  },
);

/**
 * パックの通報を記録する（v1は記録のみ、Rhing運営がFirebase console等で
 * 手動レビューする）。stickerPackReportsもクライアントからの読み書きは
 * 一律禁止のため、記録はこのcallableを経由する。
 */
export const createStickerPackReport = onCall(
  { region: "asia-northeast1" },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }
    const packId = request.data?.packId;
    if (typeof packId !== "string" || !packId) {
      throw new HttpsError("invalid-argument", "packIdが必要です");
    }
    const reason = request.data?.reason;
    if (typeof reason !== "string" || !reason.trim()) {
      throw new HttpsError("invalid-argument", "reasonが必要です");
    }
    const packDoc = await db.collection("stickerPacks").doc(packId).get();
    if (!packDoc.exists) {
      throw new HttpsError("not-found", "パックが見つかりません");
    }
    await db.collection("stickerPackReports").add({
      packId,
      reporterUid: uid,
      reason: reason.trim().slice(0, 1000),
      createdAt: FieldValue.serverTimestamp(),
    });
  },
);

/** Firebase Storageのダウンロード URL から `/o/` 以降のオブジェクトパスを取り出す。 */
function storagePathFromDownloadUrl(url: string): string | null {
  const match = url.match(/\/o\/([^?]+)/);
  return match ? decodeURIComponent(match[1]) : null;
}

/**
 * 出品者が自分のパックを削除する。誰か1人でも現在所有していれば
 * （ownerCount > 0）削除できない（購入済みユーザーの手持ちスタンプを
 * 消さないため）。ストレージ上の画像も併せてベストエフォートで削除する。
 */
export const deleteStickerPack = onCall(
  { region: "asia-northeast1" },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }
    const packId = request.data?.packId;
    if (typeof packId !== "string" || !packId) {
      throw new HttpsError("invalid-argument", "packIdが必要です");
    }
    const ref = db.collection("stickerPacks").doc(packId);
    const doc = await ref.get();
    if (!doc.exists) {
      throw new HttpsError("not-found", "パックが見つかりません");
    }
    const data = doc.data()!;
    if (data.creatorId !== uid) {
      throw new HttpsError("permission-denied", "自分が出品したパックのみ削除できます");
    }
    const ownerCount = typeof data.ownerCount === "number" ? data.ownerCount : 0;
    if (ownerCount > 0) {
      throw new HttpsError(
        "failed-precondition",
        "このパックは現在利用しているユーザーがいるため削除できません",
      );
    }

    await ref.delete();

    const stickers = (data.stickers as { imageUrl: string }[] | undefined) ?? [];
    const bucket = getStorage().bucket();
    await Promise.all(
      stickers.map(async (s) => {
        const path = storagePathFromDownloadUrl(s.imageUrl);
        if (!path) return;
        try {
          await bucket.file(path).delete({ ignoreNotFound: true });
        } catch (err) {
          logger.warn(`ストレージオブジェクトの削除に失敗しました: ${path}`, err);
        }
      }),
    );
  },
);

// ---------------------------------------------------------------------
// daidai横丁: 購入付与フロー（2026-08-11追加）。無料パックの直接付与・
// 有料パックのStripe Checkout経由の付与、どちらも最終的にこの
// grantOwnershipを通る。ownedStickerPacksの存在チェックで、Webhookの
// 再送（Stripeは同一イベントを複数回配信しうる）による二重付与を防ぐ。
// ---------------------------------------------------------------------
async function grantOwnership(
  uid: string,
  packId: string,
  packRef: FirebaseFirestore.DocumentReference,
): Promise<void> {
  const ownedRef = db
    .collection("users")
    .doc(uid)
    .collection("ownedStickerPacks")
    .doc(packId);
  await db.runTransaction(async (tx) => {
    const ownedDoc = await tx.get(ownedRef);
    if (ownedDoc.exists) return;
    tx.set(ownedRef, { packId, grantedAt: FieldValue.serverTimestamp() });
    tx.update(packRef, {
      ownerCount: FieldValue.increment(1),
      salesCount: FieldValue.increment(1),
    });
  });
}

/**
 * ユーザーが所有しているペタピタパックをアンインストール（所有解除）する。
 * grantOwnershipの対称形として、ownedStickerPacksドキュメントを削除し
 * ownerCountを1減らす（2026-08-11追加、functions/src/index.tsのcreateStickerPack
 * コメントで予告していたアンインストール連動の実処理）。salesCountは
 * 「これまでの累計販売数」という別の指標のため変更しない。これによって
 * ownerCountが0に戻れば、出品者はdeleteStickerPackでパックを削除できるように
 * なる。無料・有料どちらのパックでも、PAID_PACKS_ENABLEDに関係なく常に許可する。
 */
export const uninstallStickerPack = onCall(
  { region: "asia-northeast1" },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }
    const packId = request.data?.packId;
    if (typeof packId !== "string" || !packId) {
      throw new HttpsError("invalid-argument", "packIdが必要です");
    }

    const packRef = db.collection("stickerPacks").doc(packId);
    const ownedRef = db
      .collection("users")
      .doc(uid)
      .collection("ownedStickerPacks")
      .doc(packId);

    await db.runTransaction(async (tx) => {
      // Firestoreトランザクションは全てのgetをset/update/deleteより先に
      // 行う必要があるため、2つのドキュメントを先にまとめて読む。
      const ownedDoc = await tx.get(ownedRef);
      const packDoc = await tx.get(packRef);

      if (!ownedDoc.exists) {
        throw new HttpsError("failed-precondition", "このパックは所有していません");
      }
      tx.delete(ownedRef);

      if (packDoc.exists) {
        const currentOwnerCount =
          typeof packDoc.data()?.ownerCount === "number" ? packDoc.data()!.ownerCount : 0;
        tx.update(packRef, { ownerCount: Math.max(0, currentOwnerCount - 1) });
      }
    });
  },
);

// HomePage-Rhingの本番/開発ドメインのみ、Stripe Checkoutの戻り先として許可する。
const ALLOWED_RETURN_ORIGINS = ["https://rhing.jp", "http://localhost:3000"];

function resolveReturnOrigin(candidate: unknown): string {
  if (typeof candidate === "string" && ALLOWED_RETURN_ORIGINS.includes(candidate)) {
    return candidate;
  }
  return ALLOWED_RETURN_ORIGINS[0];
}

/**
 * パックの入手を開始する。無料パック（price===0）はStripeを介さず直接
 * 付与し、有料パックはStripe Checkout Session（都度払い）を作成してその
 * URLを返す。決済確定後の実付与はstripeWebhookが行う。
 */
export const createCheckoutSession = onCall(
  { region: "asia-northeast1", secrets: [stripeSecretKey] },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }
    const packId = request.data?.packId;
    if (typeof packId !== "string" || !packId) {
      throw new HttpsError("invalid-argument", "packIdが必要です");
    }

    const packRef = db.collection("stickerPacks").doc(packId);
    const packDoc = await packRef.get();
    if (!packDoc.exists) {
      throw new HttpsError("not-found", "パックが見つかりません");
    }
    const pack = packDoc.data()!;

    const ownedRef = db
      .collection("users")
      .doc(uid)
      .collection("ownedStickerPacks")
      .doc(packId);
    if ((await ownedRef.get()).exists) {
      throw new HttpsError("already-exists", "このパックはすでに入手済みです");
    }

    const price = typeof pack.price === "number" ? pack.price : 0;
    if (price > 0 && !PAID_PACKS_ENABLED) {
      throw new HttpsError("failed-precondition", PAID_PACKS_DISABLED_MESSAGE);
    }
    if (price <= 0) {
      await grantOwnership(uid, packId, packRef);
      return { granted: true };
    }

    const origin = resolveReturnOrigin(request.data?.origin);
    const session = await getStripeClient().checkout.sessions.create({
      mode: "payment",
      payment_method_types: ["card"],
      line_items: [
        {
          price_data: {
            currency: "jpy",
            product_data: {
              name: typeof pack.name === "string" ? pack.name : "ペタピタパック",
            },
            unit_amount: price,
          },
          quantity: 1,
        },
      ],
      metadata: { uid, packId },
      success_url: `${origin}/daidai-yokocho/${packId}?purchase=success`,
      cancel_url: `${origin}/daidai-yokocho/${packId}?purchase=cancel`,
    });
    return { url: session.url };
  },
);

/**
 * Stripeからの決済完了通知を受け取り、ペタピタパックを購入者に付与する。
 * HomePage-Rhingは決済へのリダイレクトのみを担当し、実際のFirestore書き込みは
 * ここ（DaiDai既存のCloud Functions）で行う方針（技術仕様書7.4節参照）。
 */
export const stripeWebhook = onRequest(
  { region: "asia-northeast1", secrets: [stripeSecretKey, stripeWebhookSecret] },
  async (req, res) => {
    const sig = req.headers["stripe-signature"];
    if (typeof sig !== "string") {
      res.status(400).send("stripe-signatureヘッダーがありません");
      return;
    }

    let event: Stripe.Event;
    try {
      event = getStripeClient().webhooks.constructEvent(
        req.rawBody,
        sig,
        stripeWebhookSecret.value(),
      );
    } catch (err) {
      logger.error("Stripe Webhookの署名検証に失敗しました:", err);
      res.status(400).send(`Webhook Error: ${(err as Error).message}`);
      return;
    }

    if (event.type === "checkout.session.completed") {
      const session = event.data.object as Stripe.Checkout.Session;
      const uid = session.metadata?.uid;
      const packId = session.metadata?.packId;
      if (uid && packId) {
        const packRef = db.collection("stickerPacks").doc(packId);
        const packDoc = await packRef.get();
        if (packDoc.exists) {
          await grantOwnership(uid, packId, packRef);
        } else {
          logger.error(`Webhook: stickerPacks/${packId} が見つかりません`);
        }
      } else {
        logger.error("Webhook: checkout.session.completedにuid/packIdのmetadataがありません");
      }
    }

    res.json({ received: true });
  },
);

// ---------------------------------------------------------------------
// 運営向け管理画面（2026-08-12追加）。管理者判定はFirebase Custom Claims
// （admin: true）。DaiDaiはOAuth専用でメール・パスワード認証を持たないため、
// 管理者専用の別ログインは作らず、既存のDaiDaiアカウントにクレームを
// 付与する形にした。
// ---------------------------------------------------------------------

/**
 * 初回管理者登録（一時的な機能）。`system/adminBootstrap`の`consumed`
 * フラグを見て、未消費なら呼び出し元にadmin: trueのカスタムクレームを
 * 付与しフラグを消費する。最初に呼んだ人だけが管理者になれる、という
 * ブートストラップ専用の一度きりの仕組み（CLAUDE.md記載の「一度きりの
 * Cloud Functions」パターンをアプリのUIから安全に行えるようにしたもの）。
 * 運営が管理者になったことを確認したら、この関数自体をソースから削除し、
 * `firebase functions:delete grantFirstAdminOnce --region asia-northeast1
 * --force`で後始末する。
 */
export const grantFirstAdminOnce = onCall(
  { region: "asia-northeast1" },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }
    const flagRef = db.collection("system").doc("adminBootstrap");
    const granted = await db.runTransaction(async (transaction) => {
      const flagSnap = await transaction.get(flagRef);
      if (flagSnap.exists && flagSnap.data()?.consumed === true) {
        return false;
      }
      transaction.set(flagRef, {
        consumed: true,
        grantedTo: uid,
        grantedAt: FieldValue.serverTimestamp(),
      });
      return true;
    });
    if (!granted) {
      throw new HttpsError(
        "failed-precondition",
        "既に管理者が設定されています",
      );
    }
    await getAuth().setCustomUserClaims(uid, { admin: true });
    logger.info(`初回管理者を付与: ${uid}`);
    return { granted: true };
  },
);

/**
 * 指定ユーザーのアカウントを停止/解除する（管理者のみ）。停止時は
 * 既存セッションを即座に無効化するため`revokeRefreshTokens`も呼ぶ
 * （AuthGateのaccountStatusチェックは次回のFirestore読み込み待ちに
 * なるため、実際のログイン不可はrevokeRefreshTokens、UI側の表示切替は
 * accountStatus、という2段構え）。
 */
export const suspendUserAccount = onCall(
  { region: "asia-northeast1" },
  async (request) => {
    if (request.auth?.token.admin !== true) {
      throw new HttpsError("permission-denied", "管理者のみ実行できます");
    }
    const targetUserId = request.data?.targetUserId;
    if (typeof targetUserId !== "string" || !targetUserId) {
      throw new HttpsError("invalid-argument", "targetUserIdが必要です");
    }
    const suspend = request.data?.suspend;
    if (typeof suspend !== "boolean") {
      throw new HttpsError("invalid-argument", "suspendが必要です");
    }
    await db.collection("users").doc(targetUserId).update({
      accountStatus: suspend ? "suspended" : "active",
    });
    if (suspend) {
      await getAuth()
        .revokeRefreshTokens(targetUserId)
        .catch((error) => {
          // Firebase Auth側にユーザーが存在しない等は無視する
          // （Firestore側の状態変更は既に完了しているため）。
          logger.warn(`revokeRefreshTokensに失敗: ${targetUserId}`, error);
        });
    }
    logger.info(`アカウント${suspend ? "停止" : "解除"}: ${targetUserId}`);
  },
);

/**
 * 一度きりの移行処理: `accountStatus`フィールドが物理的に存在しない
 * 古いユーザードキュメント（2026-07-28のアカウント削除機能実装より前に
 * 作られたアカウント）に`accountStatus: "active"`をバックフィルする。
 * `broadcastAnnouncement`の`.where("accountStatus", "==", "active")`が、
 * フィールド自体が存在しないドキュメントをFirestoreの仕様上マッチさせない
 * ため、便りの配信対象から静かに漏れてしまう不具合の恒久対応。
 * 実行・べき対性の確認（2回目に`backfilled: 0`になること）が済んだら、
 * `grantFirstAdminOnce`等と同様にソースから削除し、
 * `firebase functions:delete backfillAccountStatusOnce --region asia-northeast1 --force`
 * で後始末する。
 */
export const backfillAccountStatusOnce = onCall(
  { region: "asia-northeast1", timeoutSeconds: 300 },
  async (request) => {
    if (request.auth?.token.admin !== true) {
      throw new HttpsError("permission-denied", "管理者のみ実行できます");
    }
    const usersSnapshot = await db.collection("users").get();
    const writer = new ChunkedWriter();
    let backfilled = 0;
    for (const doc of usersSnapshot.docs) {
      if (!("accountStatus" in doc.data())) {
        await writer.update(doc.ref, { accountStatus: "active" });
        backfilled += 1;
      }
    }
    await writer.commit();
    logger.info(
      `accountStatusバックフィル: ${backfilled}/${usersSnapshot.size}件`,
    );
    return { scanned: usersSnapshot.size, backfilled };
  },
);

/** 便り（公式アカウント）の固定UID・Rhing ID。 */
const OFFICIAL_ACCOUNT_UID = "official-tayori";
const OFFICIAL_ACCOUNT_RHING_ID = "tayori";

/**
 * 便り（公式アカウント）用の`users/{OFFICIAL_ACCOUNT_UID}`ドキュメントが
 * 無ければ作成する。Firebase Authに対応する実アカウントは持たない
 * （送信者表示は`users/{senderId}`をライブ参照するだけのため、Firestore
 * ドキュメントのみで既存UIがそのまま正しく描画できる）。アイコンは未設定の
 * ままにし、Rhing IDから導出される色付きイニシャルへのフォールバック表示
 * に任せる。
 */
async function ensureOfficialAccount(): Promise<void> {
  const ref = db.collection("users").doc(OFFICIAL_ACCOUNT_UID);
  const doc = await ref.get();
  if (doc.exists) return;
  await ref.set({
    userId: OFFICIAL_ACCOUNT_UID,
    rhingId: OFFICIAL_ACCOUNT_RHING_ID,
    displayName: null,
    icons: [],
    backgroundImages: [],
    statusMessages: [],
    nicknames: [{ id: "official", text: "便り" }],
    snsLinks: [],
    profileCards: [],
    activeIconId: null,
    activeBackgroundImageId: null,
    activeStatusMessageId: null,
    activeNicknameId: "official",
    activeProfileCardId: null,
    conversationProfileCardId: {},
    preferences: {},
    accountStatus: "active",
    deletionRequestedAt: null,
    createdAt: FieldValue.serverTimestamp(),
    lastLoginAt: null,
  });
}

/**
 * 全住人（稼働中=accountStatus:'active'のアカウントのみ）に、便り
 * アカウントからの一対メッセージとしてお知らせを配信する（管理者のみ）。
 * DirectMessage/DmRoom/Messageのスキーマ・書き込み方は
 * `getOrCreateDirectMessage`/`sendTextMessage`
 * （lib/repositories/direct_message_repository.dart）と揃える。dmIdは
 * クライアント側の`DirectMessage.idFor`と同じ決定的なpairId方式のため、
 * 2回目以降の配信も既存の一対の続きとして届く。
 */
export const broadcastAnnouncement = onCall(
  { region: "asia-northeast1", timeoutSeconds: 300 },
  async (request) => {
    if (request.auth?.token.admin !== true) {
      throw new HttpsError("permission-denied", "管理者のみ実行できます");
    }
    const message = request.data?.message;
    if (typeof message !== "string" || !message.trim()) {
      throw new HttpsError("invalid-argument", "messageが必要です");
    }

    await ensureOfficialAccount();

    const usersSnapshot = await db
      .collection("users")
      .where("accountStatus", "==", "active")
      .get();

    const writer = new ChunkedWriter();
    let count = 0;
    for (const userDoc of usersSnapshot.docs) {
      const userId = userDoc.id;
      if (userId === OFFICIAL_ACCOUNT_UID) continue;
      const rhingId: string | undefined = userDoc.data().rhingId;

      const sortedIds = [OFFICIAL_ACCOUNT_UID, userId].sort();
      const dmId = `${sortedIds[0]}_${sortedIds[1]}`;
      const dmRef = db.collection("directMessages").doc(dmId);
      const dmDoc = await dmRef.get();

      let roomId: string;
      if (dmDoc.exists && dmDoc.data()?.defaultRoomId) {
        roomId = dmDoc.data()!.defaultRoomId;
      } else {
        const newRoomRef = dmRef.collection("rooms").doc();
        roomId = newRoomRef.id;
        await writer.set(dmRef, {
          participants: [OFFICIAL_ACCOUNT_UID, userId],
          participantRhingIds: {
            [OFFICIAL_ACCOUNT_UID]: OFFICIAL_ACCOUNT_RHING_ID,
            [userId]: rhingId ?? userId,
          },
          defaultRoomId: roomId,
          lastMessageAt: FieldValue.serverTimestamp(),
          severanceRequestedBy: null,
          readReceiptsEnabled: true,
          readReceiptsProposalBy: null,
          accountDeletedUserId: null,
          roomsEnabled: false,
        });
        await writer.set(newRoomRef, {
          dmId,
          name: "メイン",
          participants: [OFFICIAL_ACCOUNT_UID, userId],
          lastMessageAt: FieldValue.serverTimestamp(),
          createdAt: FieldValue.serverTimestamp(),
          deletionRequestedBy: null,
        });
      }

      const roomRef = dmRef.collection("rooms").doc(roomId);
      const messageRef = roomRef.collection("messages").doc();
      await writer.set(messageRef, {
        conversationId: roomId,
        conversationType: "dm",
        senderId: OFFICIAL_ACCOUNT_UID,
        senderRhingId: OFFICIAL_ACCOUNT_RHING_ID,
        content: message,
        contentType: "text",
        sentAt: FieldValue.serverTimestamp(),
        hiddenFor: [],
        readBy: [],
        isSpam: false,
        silent: false,
        replyToMessageId: null,
        replyToSenderId: null,
        replyToSenderRhingId: null,
        replyToSnippet: null,
        editedAt: null,
        reactions: {},
        callStartedAt: null,
        callDurationSeconds: null,
        callIsVideo: null,
        accountDeletionResponse: null,
      });
      if (dmDoc.exists) {
        await writer.update(roomRef, {
          lastMessageAt: FieldValue.serverTimestamp(),
        });
        await writer.update(dmRef, {
          lastMessageAt: FieldValue.serverTimestamp(),
        });
      }
      count += 1;
    }
    await writer.commit();
    logger.info(`お知らせを${count}件の一対に配信しました`);
    return { count };
  },
);
