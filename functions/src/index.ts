import { createHash, randomUUID } from "crypto";
import * as fs from "fs";
import * as os from "os";
import * as path from "path";

import { initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import {
  FieldValue,
  getFirestore,
  Timestamp,
  type WriteBatch,
} from "firebase-admin/firestore";
import { getMessaging } from "firebase-admin/messaging";
import { getStorage } from "firebase-admin/storage";
import {
  type AuthenticatorTransportFuture,
  generateAuthenticationOptions,
  generateRegistrationOptions,
  verifyAuthenticationResponse,
  verifyRegistrationResponse,
} from "@simplewebauthn/server";
import bcrypt from "bcryptjs";
import { logger } from "firebase-functions";
import { defineSecret, defineString } from "firebase-functions/params";
import {
  onDocumentCreated,
  onDocumentWritten,
} from "firebase-functions/v2/firestore";
import { HttpsError, onCall, onRequest } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { onObjectFinalized } from "firebase-functions/v2/storage";
import ffmpeg from "fluent-ffmpeg";
import ffmpegPath from "ffmpeg-static";
import Stripe from "stripe";

import {
  WEBHOOK_BODY_MAX_BYTES,
  WEBHOOK_MAX_PER_GROUP,
  canManageBots,
  generateWebhookToken,
  hashWebhookToken,
  nextRateState,
  normalizeWebhookName,
  parseWebhookPath,
  parseWebhookPayload,
  verifyWebhookToken,
  webhookSenderId,
} from "./webhook";
import {
  type SkippedTarget,
  classifyTarget,
  normalizeBulkTargets,
  parseProfileViewRequest,
} from "./adminUsers";
import { renderOgImage } from "./ogImage";

if (ffmpegPath) ffmpeg.setFfmpegPath(ffmpegPath);

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
  const rhingSeed: string | undefined = userData.rhingSeed;
  const writer = new ChunkedWriter();

  await notifyDirectMessages(userId, rhingSeed, writer);
  await notifyAndLeaveGroups(userId, rhingSeed, writer);
  await deleteFriends(userId, writer);
  await deleteFriendRequests(userId, writer);

  if (rhingSeed) {
    await writer.delete(db.collection("userInvites").doc(rhingSeed));
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
 * この一対で最も古い（createdAtが最小の）寄合に投稿する（どの寄合を
 * 開いていても内容が分かるようにするため、2026-09-14変更、以前は
 * defaultRoomIdを直接参照していた）。メッセージ・寄合・DMドキュメント自体は
 * ここでは削除しない（もう一方の参加者がチャット画面で「はい」を選んだ
 * 場合のみクライアント側で物理削除される。
 * DirectMessageRepository.deleteDmAfterAccountDeletion参照）。 */
async function notifyDirectMessages(
  userId: string,
  rhingSeed: string | undefined,
  writer: ChunkedWriter,
): Promise<void> {
  const dms = await db
    .collection("directMessages")
    .where("participants", "array-contains", userId)
    .get();

  for (const dm of dms.docs) {
    const oldestRoom = await dm.ref
      .collection("rooms")
      .orderBy("createdAt")
      .limit(1)
      .get();
    if (oldestRoom.empty) continue;
    const targetRoomId = oldestRoom.docs[0].id;

    const roomRef = dm.ref.collection("rooms").doc(targetRoomId);
    const messageRef = roomRef.collection("messages").doc();
    await writer.set(messageRef, {
      conversationId: targetRoomId,
      conversationType: "dm",
      senderId: userId,
      senderRhingSeed: rhingSeed ?? null,
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
  rhingSeed: string | undefined,
  writer: ChunkedWriter,
): Promise<void> {
  const groups = await db
    .collection("groups")
    .where("memberIds", "array-contains", userId)
    .get();

  for (const group of groups.docs) {
    const groupData = group.data();
    const oldestRoom = await group.ref
      .collection("rooms")
      .orderBy("createdAt")
      .limit(1)
      .get();
    if (oldestRoom.empty) continue;
    const targetRoomId = oldestRoom.docs[0].id;

    const roomRef = group.ref.collection("rooms").doc(targetRoomId);
    const messageRef = roomRef.collection("messages").doc();
    await writer.set(messageRef, {
      conversationId: targetRoomId,
      conversationType: "room",
      senderId: userId,
      senderRhingSeed: rhingSeed ?? null,
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
// パスキー（WebAuthn）によるRhing Seedログイン・新規アカウント作成
// （2026-09-16実装。CLAUDE.md「ログイン手段の方針」の将来検討事項として
// 構想されていた「Rhing Seed＋パスキー」の実装。メールアドレス・電話番号を
// 一切使わず、DaiDai自身がWebAuthnのRelying Partyになる）。
//
// QRコードログイン（claimQrLoginSession等、上記）と同じ「独自検証→
// admin.auth().createCustomToken(uid)発行→クライアントでsignInWithCustomToken」
// という型を踏襲する。クライアント側の実装は
// `lib/repositories/auth_repository.dart`の`registerWithPasskey`/
// `signInWithPasskey`参照。
//
// 対象プラットフォームはWeb/Android/iOS/macOS/Windowsの5つ（Linuxはパスキー
// 非対応、`lib/utils/platform_info.dart`の`isPasskeyCapablePlatform`で
// 導線ごと非表示にする）。パスキー紛失時の復旧（秘密の質問）・複数パスキー
// 管理（追加登録・一覧・削除）は2026-09-16に追加実装した（本セクション後半）。
// ---------------------------------------------------------------------

// RPドメイン・許可オリジンは非シークレット値のため`defineSecret`ではなく
// `defineString`で管理する。本番（daidai-rhing）には`.env.daidai-rhing`で
// 本番ドメイン（dai-dai-phi.vercel.app）の値を上書きデプロイ済み
// （2026-09-18、それまでlocalhost固定のままで本番のパスキー機能が
// 全て失敗していた）。ここのデフォルト値はローカル開発（localhost）
// 向けのフォールバックとして残す。
const passkeyRpId = defineString("PASSKEY_RP_ID", { default: "localhost" });
const passkeyAllowedOrigins = defineString("PASSKEY_ALLOWED_ORIGINS", {
  default: "http://localhost:8765",
});

function getPasskeyAllowedOrigins(): string[] {
  return passkeyAllowedOrigins
    .value()
    .split(",")
    .map((origin) => origin.trim())
    .filter((origin) => origin.length > 0);
}

const PASSKEY_NAME_MAX_LENGTH = 30;

/**
 * 住人が付けるパスキーの名前を正規化する（2026-09-18追加）。文字列以外・
 * 前後空白を除くと空になる場合は「名前無し」として`null`を返し、一覧では
 * 作成日時にフォールバック表示する。
 */
function normalizePasskeyName(value: unknown): string | null {
  if (typeof value !== "string") {
    return null;
  }
  const trimmed = value.trim().slice(0, PASSKEY_NAME_MAX_LENGTH);
  return trimmed.length > 0 ? trimmed : null;
}

const PASSKEY_CHALLENGE_TTL_MS = 5 * 60 * 1000;

/**
 * チャレンジドキュメントを取得し、種別とTTLを検証したうえで即座に削除する
 * （検証前に消費することで、同じchallengeIdでの二重呼び出し・リプレイの
 * 余地を最小化する）。戻り値はチャレンジに紐づく`uid`と`challenge`文字列。
 */
async function consumePasskeyChallenge(
  challengeId: string,
  expectedType: "registration" | "authentication" | "addCredential",
): Promise<{ uid: string; challenge: string }> {
  const challengeRef = db.collection("passkeyChallenges").doc(challengeId);
  const challengeDoc = await challengeRef.get();
  if (!challengeDoc.exists) {
    throw new HttpsError("not-found", "チャレンジが見つかりません");
  }
  const data = challengeDoc.data()!;
  await challengeRef.delete();
  if (data.type !== expectedType) {
    throw new HttpsError("failed-precondition", "不正なチャレンジです");
  }
  const createdAt = data.createdAt as Timestamp | undefined;
  if (
    !createdAt ||
    Date.now() - createdAt.toMillis() > PASSKEY_CHALLENGE_TTL_MS
  ) {
    throw new HttpsError("deadline-exceeded", "チャレンジの有効期限が切れています");
  }
  return { uid: data.uid as string, challenge: data.challenge as string };
}

/**
 * Conditional UI（パスワードマネージャー自動候補表示、2026-09-16追加）向けの
 * チャレンジ消費版。discoverable credential方式ではユーザーを事前に特定
 * できないため`uid`を持たない点だけが[consumePasskeyChallenge]と異なる。
 */
async function consumeDiscoverablePasskeyChallenge(
  challengeId: string,
): Promise<{ challenge: string }> {
  const challengeRef = db.collection("passkeyChallenges").doc(challengeId);
  const challengeDoc = await challengeRef.get();
  if (!challengeDoc.exists) {
    throw new HttpsError("not-found", "チャレンジが見つかりません");
  }
  const data = challengeDoc.data()!;
  await challengeRef.delete();
  if (data.type !== "authenticationDiscoverable") {
    throw new HttpsError("failed-precondition", "不正なチャレンジです");
  }
  const createdAt = data.createdAt as Timestamp | undefined;
  if (
    !createdAt ||
    Date.now() - createdAt.toMillis() > PASSKEY_CHALLENGE_TTL_MS
  ) {
    throw new HttpsError("deadline-exceeded", "チャレンジの有効期限が切れています");
  }
  return { challenge: data.challenge as string };
}

/**
 * Rhing Seed＋パスキーによる新規アカウント作成の第1段階
 * （`AuthRepository.registerWithPasskey`から呼ぶ）。まだFirebase Auth
 * ユーザーは作らず、WebAuthnのregistration challengeだけを発行する
 * （実際のユーザー作成は`finishPasskeyRegistration`で行う）。
 */
export const beginPasskeyRegistration = onCall(
  { region: "asia-northeast1" },
  async () => {
    const uid = randomUUID();
    const options = await generateRegistrationOptions({
      rpName: "DaiDai",
      rpID: passkeyRpId.value(),
      userName: uid,
      userID: Buffer.from(uid, "utf8"),
      attestationType: "none",
      authenticatorSelection: {
        residentKey: "preferred",
        userVerification: "required",
      },
    });
    const challengeRef = await db.collection("passkeyChallenges").add({
      type: "registration",
      uid,
      challenge: options.challenge,
      createdAt: FieldValue.serverTimestamp(),
    });
    return { challengeId: challengeRef.id, options };
  },
);

/**
 * 新規アカウント作成の第2段階。デバイスで生成されたattestationResponseを
 * 検証し、成功したらFirebase Authユーザーを新規作成してカスタムトークンを
 * 返す。この時点ではFirestoreに`users/{uid}`ドキュメントはまだ作らない
 * （Google/Apple/QRログインと同じく、`AuthGate`がTermsConsentScreen→
 * RhingSeedSetupScreenへ自然に遷移させるのに任せる設計）。
 */
export const finishPasskeyRegistration = onCall(
  { region: "asia-northeast1" },
  async (request) => {
    const challengeId = request.data?.challengeId;
    const attestationResponse = request.data?.attestationResponse;
    if (
      typeof challengeId !== "string" ||
      !challengeId ||
      !attestationResponse
    ) {
      throw new HttpsError(
        "invalid-argument",
        "challengeId/attestationResponseが必要です",
      );
    }
    const { uid, challenge } = await consumePasskeyChallenge(
      challengeId,
      "registration",
    );

    let verification;
    try {
      verification = await verifyRegistrationResponse({
        response: attestationResponse,
        expectedChallenge: challenge,
        expectedOrigin: getPasskeyAllowedOrigins(),
        expectedRPID: passkeyRpId.value(),
      });
    } catch (error) {
      logger.warn("パスキー登録の検証に失敗", error);
      throw new HttpsError("invalid-argument", "パスキーの検証に失敗しました");
    }
    if (!verification.verified || !verification.registrationInfo) {
      throw new HttpsError("invalid-argument", "パスキーの検証に失敗しました");
    }

    const { credential, credentialDeviceType, credentialBackedUp } =
      verification.registrationInfo;

    await getAuth().createUser({ uid });
    await db
      .collection("users")
      .doc(uid)
      .collection("passkeyCredentials")
      .doc(credential.id)
      .set({
        publicKey: Buffer.from(credential.publicKey),
        counter: credential.counter,
        transports: credential.transports ?? [],
        deviceType: credentialDeviceType,
        backedUp: credentialBackedUp,
        createdAt: FieldValue.serverTimestamp(),
        lastUsedAt: null,
      });

    const customToken = await getAuth().createCustomToken(uid);
    return { customToken };
  },
);

/**
 * Rhing Seed＋パスキーでのログインの第1段階（`AuthRepository.signInWithPasskey`
 * から呼ぶ）。指定されたRhing Seedに登録済みのパスキーでauthentication
 * challengeを発行する。
 */
export const beginPasskeyAuthentication = onCall(
  { region: "asia-northeast1" },
  async (request) => {
    // rhingId→rhingSeedへの改名に伴う移行期間シム（2026-09-23追加）。
    // クライアント（Web）のデプロイが完了するまでの一瞬、旧キー`rhingId`で
    // 送られてくる可能性があるため両方受け付ける。クライアントの動作確認が
    // 済んだら`request.data?.rhingId`のフォールバックを削除すること。
    const rhingSeed = request.data?.rhingSeed ?? request.data?.rhingId;
    if (typeof rhingSeed !== "string" || !rhingSeed) {
      throw new HttpsError("invalid-argument", "rhingSeedが必要です");
    }
    const usersSnapshot = await db
      .collection("users")
      .where("rhingSeed", "==", rhingSeed.trim().toLowerCase())
      .limit(1)
      .get();
    if (usersSnapshot.empty) {
      throw new HttpsError(
        "not-found",
        "そのRhing Seedのアカウントが見つかりません",
      );
    }
    const uid = usersSnapshot.docs[0].id;
    const credentialsSnapshot = await db
      .collection("users")
      .doc(uid)
      .collection("passkeyCredentials")
      .get();
    if (credentialsSnapshot.empty) {
      throw new HttpsError(
        "failed-precondition",
        "このアカウントにはパスキーが登録されていません",
      );
    }
    const allowCredentials = credentialsSnapshot.docs.map((doc) => ({
      id: doc.id,
      transports: (doc.data().transports ??
        []) as AuthenticatorTransportFuture[],
    }));
    const options = await generateAuthenticationOptions({
      rpID: passkeyRpId.value(),
      allowCredentials,
      userVerification: "required",
    });
    const challengeRef = await db.collection("passkeyChallenges").add({
      type: "authentication",
      uid,
      challenge: options.challenge,
      createdAt: FieldValue.serverTimestamp(),
    });
    return { challengeId: challengeRef.id, options };
  },
);

/**
 * ログインの第2段階。assertionResponseを検証し、成功したらカスタムトークンを
 * 返す。
 */
export const finishPasskeyAuthentication = onCall(
  { region: "asia-northeast1" },
  async (request) => {
    const challengeId = request.data?.challengeId;
    const assertionResponse = request.data?.assertionResponse;
    if (
      typeof challengeId !== "string" ||
      !challengeId ||
      !assertionResponse
    ) {
      throw new HttpsError(
        "invalid-argument",
        "challengeId/assertionResponseが必要です",
      );
    }
    const { uid, challenge } = await consumePasskeyChallenge(
      challengeId,
      "authentication",
    );
    const credentialId = assertionResponse.id as string | undefined;
    if (!credentialId) {
      throw new HttpsError("invalid-argument", "不正なパスキー応答です");
    }
    const credentialRef = db
      .collection("users")
      .doc(uid)
      .collection("passkeyCredentials")
      .doc(credentialId);
    const credentialDoc = await credentialRef.get();
    if (!credentialDoc.exists) {
      throw new HttpsError("not-found", "パスキーが見つかりません");
    }
    const credentialData = credentialDoc.data()!;

    let verification;
    try {
      verification = await verifyAuthenticationResponse({
        response: assertionResponse,
        expectedChallenge: challenge,
        expectedOrigin: getPasskeyAllowedOrigins(),
        expectedRPID: passkeyRpId.value(),
        credential: {
          id: credentialId,
          publicKey: new Uint8Array(credentialData.publicKey as Buffer),
          counter: credentialData.counter as number,
          transports:
            credentialData.transports as AuthenticatorTransportFuture[],
        },
      });
    } catch (error) {
      logger.warn("パスキー認証の検証に失敗", error);
      throw new HttpsError("invalid-argument", "パスキーの検証に失敗しました");
    }
    if (!verification.verified) {
      throw new HttpsError("invalid-argument", "パスキーの検証に失敗しました");
    }

    await credentialRef.update({
      counter: verification.authenticationInfo.newCounter,
      lastUsedAt: FieldValue.serverTimestamp(),
    });

    const customToken = await getAuth().createCustomToken(uid);
    return { customToken };
  },
);

/**
 * Conditional UI（パスワードマネージャー自動候補表示）によるログインの
 * 第1段階（2026-09-16追加、Web版のみ`AuthRepository`から呼ぶ）。
 * `beginPasskeyAuthentication`と異なりRhing Seedによる事前のユーザー特定を
 * 行わず、`allowCredentials`を指定しないdiscoverable credential方式の
 * challengeを発行する。どのユーザーかは`finishPasskeyAuthenticationDiscoverable`
 * 側で、assertionResponseに含まれるuserHandleから特定する
 * （`beginPasskeyRegistration`/`beginAddPasskey`が登録時にuidをそのまま
 * `userID`として埋め込んでいるため、認証応答から直接uidを復元できる）。
 */
export const beginPasskeyAuthenticationDiscoverable = onCall(
  { region: "asia-northeast1" },
  async () => {
    const options = await generateAuthenticationOptions({
      rpID: passkeyRpId.value(),
      userVerification: "required",
    });
    const challengeRef = await db.collection("passkeyChallenges").add({
      type: "authenticationDiscoverable",
      challenge: options.challenge,
      createdAt: FieldValue.serverTimestamp(),
    });
    return { challengeId: challengeRef.id, options };
  },
);

/**
 * Conditional UIログインの第2段階。assertionResponseのuserHandleを
 * base64urlデコードしてuidを復元し、そのアカウントのパスキーとして検証する。
 */
export const finishPasskeyAuthenticationDiscoverable = onCall(
  { region: "asia-northeast1" },
  async (request) => {
    const challengeId = request.data?.challengeId;
    const assertionResponse = request.data?.assertionResponse;
    if (
      typeof challengeId !== "string" ||
      !challengeId ||
      !assertionResponse
    ) {
      throw new HttpsError(
        "invalid-argument",
        "challengeId/assertionResponseが必要です",
      );
    }
    const { challenge } = await consumeDiscoverablePasskeyChallenge(
      challengeId,
    );

    const credentialId = assertionResponse.id as string | undefined;
    const rawUserHandle = assertionResponse.response?.userHandle as
      | string
      | undefined;
    if (!credentialId || !rawUserHandle) {
      throw new HttpsError("invalid-argument", "不正なパスキー応答です");
    }
    const uid = Buffer.from(rawUserHandle, "base64url").toString("utf8");

    const credentialRef = db
      .collection("users")
      .doc(uid)
      .collection("passkeyCredentials")
      .doc(credentialId);
    const credentialDoc = await credentialRef.get();
    if (!credentialDoc.exists) {
      throw new HttpsError("not-found", "パスキーが見つかりません");
    }
    const credentialData = credentialDoc.data()!;

    let verification;
    try {
      verification = await verifyAuthenticationResponse({
        response: assertionResponse,
        expectedChallenge: challenge,
        expectedOrigin: getPasskeyAllowedOrigins(),
        expectedRPID: passkeyRpId.value(),
        credential: {
          id: credentialId,
          publicKey: new Uint8Array(credentialData.publicKey as Buffer),
          counter: credentialData.counter as number,
          transports:
            credentialData.transports as AuthenticatorTransportFuture[],
        },
      });
    } catch (error) {
      logger.warn("パスキー認証（Conditional UI）の検証に失敗", error);
      throw new HttpsError("invalid-argument", "パスキーの検証に失敗しました");
    }
    if (!verification.verified) {
      throw new HttpsError("invalid-argument", "パスキーの検証に失敗しました");
    }

    await credentialRef.update({
      counter: verification.authenticationInfo.newCounter,
      lastUsedAt: FieldValue.serverTimestamp(),
    });

    const customToken = await getAuth().createCustomToken(uid);
    return { customToken };
  },
);

/**
 * 期限切れの`passkeyChallenges`を定期的に掃除する（`cleanupQrLoginSessions`と
 * 同じパターン。`consumePasskeyChallenge`が検証のたびに即削除するため
 * セキュリティ上必須ではないが、途中で放棄されたチャレンジのゴミを
 * 掃除する衛生用ジョブ）。
 */
export const cleanupPasskeyChallenges = onSchedule(
  { schedule: "every 60 minutes", region: "asia-northeast1" },
  async () => {
    const cutoff = Timestamp.fromMillis(Date.now() - PASSKEY_CHALLENGE_TTL_MS);
    const snapshot = await db
      .collection("passkeyChallenges")
      .where("createdAt", "<", cutoff)
      .get();
    const writer = new ChunkedWriter();
    for (const doc of snapshot.docs) {
      await writer.delete(doc.ref);
    }
    await writer.commit();
  },
);

// -----------------------------------------------------------------------
// パスキー紛失時の復旧（秘密の質問）・複数パスキー管理（2026-09-16追加）。
// 秘密の質問の回答はbcryptjsでハッシュ化し、`users/{uid}/secretQuestions/
// config`（Cloud Functions・Admin SDK経由の書き込み・読み取りのみ、
// firestore.rulesで`allow read, write: if false`）に保存する。CLAUDE.mdが
// 想定していた「Userモデルのフィールド」ではなく保護されたサブコレクションに
// した理由は、`users/{userId}`ドキュメント自体はログイン済みなら誰でも
// 読める設計（`allow read: if request.auth != null`）のため、直接載せると
// bcryptハッシュが他の住人から読める状態になってしまうため。
// -----------------------------------------------------------------------

/**
 * 秘密の質問の回答を比較・保存用に正規化する（前後空白除去＋小文字化）。
 * 表記ゆれの許容はこの最小限に留める。
 */
function normalizeSecretAnswer(answer: string): string {
  return answer.trim().toLowerCase();
}

const PASSKEY_RECOVERY_TTL_MS = 10 * 60 * 1000;
const RECOVERY_LOCKOUT_MAX_ATTEMPTS = 5;
const RECOVERY_LOCKOUT_DURATION_MS = 15 * 60 * 1000;

/**
 * 秘密の質問（3問固定）を設定・更新する（本人のみ）。既存の設定がある場合も
 * 3問まるごと置き換える。回答は正規化した上でbcryptハッシュ化し、平文は
 * 一切保持しない。
 */
export const setSecretQuestions = onCall(
  { region: "asia-northeast1" },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }
    const questions = request.data?.questions;
    if (
      !Array.isArray(questions) ||
      questions.length !== 3 ||
      questions.some(
        (q) =>
          typeof q?.question !== "string" ||
          !q.question.trim() ||
          typeof q?.answer !== "string" ||
          !q.answer.trim(),
      )
    ) {
      throw new HttpsError(
        "invalid-argument",
        "質問・回答の組を3つ指定してください",
      );
    }
    const hashed = await Promise.all(
      questions.map(async (q) => ({
        question: (q.question as string).trim(),
        answerHash: await bcrypt.hash(
          normalizeSecretAnswer(q.answer as string),
          10,
        ),
      })),
    );
    await db
      .collection("users")
      .doc(request.auth.uid)
      .collection("secretQuestions")
      .doc("config")
      .set({ questions: hashed, updatedAt: FieldValue.serverTimestamp() });
    return { success: true };
  },
);

/**
 * 秘密の質問の設定状況のみを返す（ハッシュ自体は返さない）。設定画面の
 * パスキー管理UIで使う。
 */
export const getSecretQuestionsStatus = onCall(
  { region: "asia-northeast1" },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }
    const doc = await db
      .collection("users")
      .doc(request.auth.uid)
      .collection("secretQuestions")
      .doc("config")
      .get();
    if (!doc.exists) {
      return { configured: false, updatedAt: null };
    }
    const updatedAt = doc.data()?.updatedAt as Timestamp | undefined;
    return { configured: true, updatedAt: updatedAt?.toMillis() ?? null };
  },
);

/**
 * 登録済みパスキーの一覧を返す（公開鍵・カウンタ等の機微情報は含めない）。
 */
export const listPasskeyCredentials = onCall(
  { region: "asia-northeast1" },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }
    const snapshot = await db
      .collection("users")
      .doc(request.auth.uid)
      .collection("passkeyCredentials")
      .get();
    return {
      credentials: snapshot.docs.map((doc) => {
        const data = doc.data();
        const createdAt = data.createdAt as Timestamp | undefined;
        const lastUsedAt = data.lastUsedAt as Timestamp | undefined;
        return {
          id: doc.id,
          deviceType: data.deviceType as string,
          backedUp: data.backedUp as boolean,
          createdAt: createdAt?.toMillis() ?? null,
          lastUsedAt: lastUsedAt?.toMillis() ?? null,
          name: (data.name as string | undefined) ?? null,
        };
      }),
    };
  },
);

/**
 * ログイン中のアカウントに追加のパスキーを登録する第1段階。
 * `beginPasskeyRegistration`と異なり新規uidは発行せず`request.auth.uid`に
 * 対してチャレンジを発行し、既存の登録済みクレデンシャルを
 * `excludeCredentials`で除外することで同じ認証器の重複登録を防ぐ。
 */
export const beginAddPasskey = onCall(
  { region: "asia-northeast1" },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }
    const uid = request.auth.uid;
    const existingSnapshot = await db
      .collection("users")
      .doc(uid)
      .collection("passkeyCredentials")
      .get();
    const excludeCredentials = existingSnapshot.docs.map((doc) => ({
      id: doc.id,
      transports: (doc.data().transports ??
        []) as AuthenticatorTransportFuture[],
    }));
    const options = await generateRegistrationOptions({
      rpName: "DaiDai",
      rpID: passkeyRpId.value(),
      userName: uid,
      userID: Buffer.from(uid, "utf8"),
      attestationType: "none",
      excludeCredentials,
      authenticatorSelection: {
        residentKey: "preferred",
        userVerification: "required",
      },
    });
    const challengeRef = await db.collection("passkeyChallenges").add({
      type: "addCredential",
      uid,
      challenge: options.challenge,
      createdAt: FieldValue.serverTimestamp(),
    });
    return { challengeId: challengeRef.id, options };
  },
);

/**
 * 追加パスキー登録の第2段階。`finishPasskeyRegistration`と異なり
 * Firebase Authユーザーの新規作成・カスタムトークン発行は行わず、
 * 既にログイン中のアカウントへクレデンシャルを追加するだけ。
 */
export const finishAddPasskey = onCall(
  { region: "asia-northeast1" },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }
    const challengeId = request.data?.challengeId;
    const attestationResponse = request.data?.attestationResponse;
    if (
      typeof challengeId !== "string" ||
      !challengeId ||
      !attestationResponse
    ) {
      throw new HttpsError(
        "invalid-argument",
        "challengeId/attestationResponseが必要です",
      );
    }
    const name = normalizePasskeyName(request.data?.name);
    const { uid, challenge } = await consumePasskeyChallenge(
      challengeId,
      "addCredential",
    );
    if (uid !== request.auth.uid) {
      throw new HttpsError("permission-denied", "不正なチャレンジです");
    }

    let verification;
    try {
      verification = await verifyRegistrationResponse({
        response: attestationResponse,
        expectedChallenge: challenge,
        expectedOrigin: getPasskeyAllowedOrigins(),
        expectedRPID: passkeyRpId.value(),
      });
    } catch (error) {
      logger.warn("パスキー追加登録の検証に失敗", error);
      throw new HttpsError("invalid-argument", "パスキーの検証に失敗しました");
    }
    if (!verification.verified || !verification.registrationInfo) {
      throw new HttpsError("invalid-argument", "パスキーの検証に失敗しました");
    }

    const { credential, credentialDeviceType, credentialBackedUp } =
      verification.registrationInfo;
    await db
      .collection("users")
      .doc(uid)
      .collection("passkeyCredentials")
      .doc(credential.id)
      .set({
        publicKey: Buffer.from(credential.publicKey),
        counter: credential.counter,
        transports: credential.transports ?? [],
        deviceType: credentialDeviceType,
        backedUp: credentialBackedUp,
        createdAt: FieldValue.serverTimestamp(),
        lastUsedAt: null,
        name,
      });
    return { success: true };
  },
);

/**
 * 登録済みパスキーを削除する（本人の分のみ）。
 */
export const deletePasskeyCredential = onCall(
  { region: "asia-northeast1" },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }
    const credentialId = request.data?.credentialId;
    if (typeof credentialId !== "string" || !credentialId) {
      throw new HttpsError("invalid-argument", "credentialIdが必要です");
    }
    await db
      .collection("users")
      .doc(request.auth.uid)
      .collection("passkeyCredentials")
      .doc(credentialId)
      .delete();
    return { success: true };
  },
);

/**
 * 登録済みパスキーの名前を変更する（本人の分のみ、2026-09-18追加）。
 */
export const renamePasskeyCredential = onCall(
  { region: "asia-northeast1" },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }
    const credentialId = request.data?.credentialId;
    if (typeof credentialId !== "string" || !credentialId) {
      throw new HttpsError("invalid-argument", "credentialIdが必要です");
    }
    const name = normalizePasskeyName(request.data?.name);
    await db
      .collection("users")
      .doc(request.auth.uid)
      .collection("passkeyCredentials")
      .doc(credentialId)
      .update({ name });
    return { success: true };
  },
);

/**
 * パスキー紛失時の復旧フロー第1段階。指定されたRhing Seedのアカウントに
 * 秘密の質問が設定されていれば、質問文（ハッシュは含まない）を返す。
 * ロックアウト中は`resource-exhausted`で拒否する。
 */
export const beginPasskeyRecovery = onCall(
  { region: "asia-northeast1" },
  async (request) => {
    // rhingId→rhingSeedへの改名に伴う移行期間シム（2026-09-23追加、
    // beginPasskeyAuthenticationと同じ理由）。クライアントの動作確認が
    // 済んだら`request.data?.rhingId`のフォールバックを削除すること。
    const rhingSeed = request.data?.rhingSeed ?? request.data?.rhingId;
    if (typeof rhingSeed !== "string" || !rhingSeed) {
      throw new HttpsError("invalid-argument", "rhingSeedが必要です");
    }
    const usersSnapshot = await db
      .collection("users")
      .where("rhingSeed", "==", rhingSeed.trim().toLowerCase())
      .limit(1)
      .get();
    if (usersSnapshot.empty) {
      throw new HttpsError(
        "not-found",
        "そのRhing Seedのアカウントが見つかりません",
      );
    }
    const uid = usersSnapshot.docs[0].id;

    const lockoutRef = db
      .collection("users")
      .doc(uid)
      .collection("recoveryLockout")
      .doc("state");
    const lockoutDoc = await lockoutRef.get();
    const lockedUntil = lockoutDoc.data()?.lockedUntil as
      | Timestamp
      | undefined;
    if (lockedUntil && lockedUntil.toMillis() > Date.now()) {
      throw new HttpsError(
        "resource-exhausted",
        "試行回数が多すぎます。しばらくしてから再度お試しください",
      );
    }

    const questionsDoc = await db
      .collection("users")
      .doc(uid)
      .collection("secretQuestions")
      .doc("config")
      .get();
    if (!questionsDoc.exists) {
      throw new HttpsError(
        "failed-precondition",
        "このアカウントには復旧手段が設定されていません",
      );
    }
    const questions = (
      questionsDoc.data()!.questions as { question: string }[]
    ).map((q) => q.question);

    const sessionRef = await db.collection("passkeyRecoverySessions").add({
      uid,
      createdAt: FieldValue.serverTimestamp(),
    });
    return { recoveryId: sessionRef.id, questions };
  },
);

/**
 * 復旧フロー第2段階。3問すべての回答が一致すればカスタムトークンを返す
 * （ユーザー確認済みの判定基準）。失敗時はロックアウトカウンタを進め、
 * 規定回数（5回）に達すると15分間ロックする。どの問いが誤りかは応答に
 * 含めない。
 */
export const finishPasskeyRecovery = onCall(
  { region: "asia-northeast1" },
  async (request) => {
    const recoveryId = request.data?.recoveryId;
    const answers = request.data?.answers;
    if (
      typeof recoveryId !== "string" ||
      !recoveryId ||
      !Array.isArray(answers) ||
      answers.length !== 3 ||
      answers.some((a) => typeof a !== "string")
    ) {
      throw new HttpsError("invalid-argument", "recoveryId/answersが必要です");
    }

    const sessionRef = db
      .collection("passkeyRecoverySessions")
      .doc(recoveryId);
    const sessionDoc = await sessionRef.get();
    if (!sessionDoc.exists) {
      throw new HttpsError("not-found", "セッションが見つかりません");
    }
    const sessionData = sessionDoc.data()!;
    await sessionRef.delete();
    const createdAt = sessionData.createdAt as Timestamp | undefined;
    if (
      !createdAt ||
      Date.now() - createdAt.toMillis() > PASSKEY_RECOVERY_TTL_MS
    ) {
      throw new HttpsError(
        "deadline-exceeded",
        "セッションの有効期限が切れています",
      );
    }
    const uid = sessionData.uid as string;

    const lockoutRef = db
      .collection("users")
      .doc(uid)
      .collection("recoveryLockout")
      .doc("state");

    const questionsDoc = await db
      .collection("users")
      .doc(uid)
      .collection("secretQuestions")
      .doc("config")
      .get();
    if (!questionsDoc.exists) {
      throw new HttpsError(
        "failed-precondition",
        "このアカウントには復旧手段が設定されていません",
      );
    }
    const storedQuestions = questionsDoc.data()!.questions as {
      answerHash: string;
    }[];

    const results = await Promise.all(
      storedQuestions.map((q, i) =>
        bcrypt.compare(normalizeSecretAnswer(answers[i] as string), q.answerHash),
      ),
    );
    const allCorrect = results.every((r) => r);

    if (!allCorrect) {
      await db.runTransaction(async (tx) => {
        const lockoutDoc = await tx.get(lockoutRef);
        const failedAttempts =
          ((lockoutDoc.data()?.failedAttempts as number | undefined) ?? 0) +
          1;
        if (failedAttempts >= RECOVERY_LOCKOUT_MAX_ATTEMPTS) {
          tx.set(lockoutRef, {
            failedAttempts: 0,
            lockedUntil: Timestamp.fromMillis(
              Date.now() + RECOVERY_LOCKOUT_DURATION_MS,
            ),
          });
        } else {
          tx.set(lockoutRef, { failedAttempts, lockedUntil: null });
        }
      });
      throw new HttpsError("invalid-argument", "入力内容が正しくありません");
    }

    await lockoutRef.delete();
    const customToken = await getAuth().createCustomToken(uid);
    return { customToken };
  },
);

/**
 * 期限切れの`passkeyRecoverySessions`を定期的に掃除する
 * （`cleanupPasskeyChallenges`と同じパターン）。
 */
export const cleanupPasskeyRecoverySessions = onSchedule(
  { schedule: "every 60 minutes", region: "asia-northeast1" },
  async () => {
    const cutoff = Timestamp.fromMillis(
      Date.now() - PASSKEY_RECOVERY_TTL_MS,
    );
    const snapshot = await db
      .collection("passkeyRecoverySessions")
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
// daidai横丁: ぺったんパッケージ関連のcallable（技術仕様書7.4・7.5参照、
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
  /**
   * メッセージ内容に応じたぺったん提案で使う役割id（`stickerRoles`
   * コレクション、`seedStickerRolesOnce`参照）のリスト。省略時は`[]`
   * （2026-09-05追加、`lib/models/sticker.dart`の`Sticker.roles`に対応）。
   */
  roles: string[];
}

/** stickersフィールドの形式（配列・各要素のstickerId/name/imageUrl/roles）を検証する。 */
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
    const roles = Array.isArray(s.roles)
      ? s.roles.filter((r): r is string => typeof r === "string")
      : [];
    return { stickerId: s.stickerId, name: s.name, imageUrl: s.imageUrl, roles };
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
    rhingSeed: typeof userData.rhingSeed === "string" ? userData.rhingSeed : "",
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
 * メッセージ内容に応じたぺったん提案（`lib/utils/sticker_suggestion.dart`
 * 参照）で使う役割定義（`stickerRoles`コレクション）を一括投入する
 * 一度きりの処理（2026-09-05追加）。役割の叩き台自体は
 * `.claude/plans/`にまとめたレビュー内容を反映しており、実行はべき等
 * （同じroleIdは`set`で上書きするだけ）。
 *
 * 既存の各ぺったん（`stickerPacks/*.stickers[].roles`）への役割の
 * 割り振りは、画像の内容確認が要る人力作業のためこの関数ではやらない
 * （Firestoreコンソールから個別に編集する）。
 *
 * 実行・確認が済んだら`grantFirstAdminOnce`等と同様にソースから削除し、
 * `firebase functions:delete seedStickerRolesOnce --region asia-northeast1 --force`
 * で後始末する。
 */
const STICKER_ROLE_SEEDS: { roleId: string; name: string; keywords: string[] }[] = [
  { roleId: "greeting", name: "挨拶", keywords: ["おはよう", "こんにちは", "こんばんは", "やあ", "よろしく"] },
  { roleId: "thanks", name: "感謝", keywords: ["ありがとう", "サンキュー", "あざす", "感謝", "助かる"] },
  { roleId: "ok", name: "了解", keywords: ["了解", "りょ", "OK", "わかった", "なるほど"] },
  { roleId: "happy", name: "嬉しい", keywords: ["やった", "よし", "いえーい", "うれしい", "最高"] },
  { roleId: "sad", name: "悲しい", keywords: ["悲しい", "つらい", "しょんぼり", "泣ける", "へこむ"] },
  { roleId: "angry", name: "怒り", keywords: ["むかつく", "許せない", "イライラ", "怒"] },
  { roleId: "surprised", name: "驚き", keywords: ["えっ", "まじで", "びっくり", "うそ", "驚いた"] },
  { roleId: "tired", name: "お疲れ様", keywords: ["おつかれ", "お疲れ様", "がんばった", "よくやった"] },
  { roleId: "sorry", name: "ごめん", keywords: ["ごめん", "すまん", "申し訳ない", "ごめんなさい"] },
  { roleId: "congrats", name: "お祝い", keywords: ["おめでとう", "祝", "やったね"] },
];

export const seedStickerRolesOnce = onCall(
  { region: "asia-northeast1" },
  async (request) => {
    if (request.auth?.token.admin !== true) {
      throw new HttpsError("permission-denied", "管理者のみ実行できます");
    }
    const writer = new ChunkedWriter();
    for (const role of STICKER_ROLE_SEEDS) {
      await writer.set(db.collection("stickerRoles").doc(role.roleId), {
        name: role.name,
        keywords: role.keywords,
      });
    }
    await writer.commit();
    logger.info(`stickerRolesシード: ${STICKER_ROLE_SEEDS.length}件`);
    return { seeded: STICKER_ROLE_SEEDS.length };
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
 * ユーザーが所有しているぺったんパックをアンインストール（所有解除）する。
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
              name: typeof pack.name === "string" ? pack.name : "ぺったんパック",
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
 * Stripeからの決済完了通知を受け取り、ぺったんパックを購入者に付与する。
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
    await writeAdminAuditLog({
      adminUid: request.auth.uid,
      action: suspend ? "suspend" : "unsuspend",
      targetUserIds: [targetUserId],
    });
    logger.info(`アカウント${suspend ? "停止" : "解除"}: ${targetUserId}`);
  },
);

/**
 * 管理者の操作の監査ログ（`adminAuditLogs`、2026-10-10追加）。誰が・いつ・
 * 誰に何をしたかを残す。Admin SDKのみが書き、クライアントからは読み書き
 * できない（firestore.rulesに該当コレクションの許可が無く既定で拒否される）。
 * 記録の失敗で操作自体を失敗させない（操作は既に完了しているため、ログだけ
 * 落とす）。
 */
async function writeAdminAuditLog(entry: {
  adminUid: string;
  action: "suspend" | "unsuspend" | "viewProfile";
  targetUserIds: string[];
  reason?: string;
  note?: string;
}): Promise<void> {
  try {
    await db.collection("adminAuditLogs").add({
      ...entry,
      createdAt: FieldValue.serverTimestamp(),
    });
  } catch (error) {
    logger.error("監査ログの記録に失敗しました", error);
  }
}

/**
 * 複数のアカウントをまとめて停止/解除する（管理者のみ、2026-10-10追加）。
 * 1回100件まで。自分自身・便り・重複・不在・削除申請中は対象外、他の管理者は
 * 停止の対象外（解除は可）。対象外にした分は理由つきで返す。停止時は
 * `suspendUserAccount`と同じく既存セッションを無効化する。
 */
export const suspendUserAccounts = onCall(
  { region: "asia-northeast1" },
  async (request) => {
    if (request.auth?.token.admin !== true) {
      throw new HttpsError("permission-denied", "管理者のみ実行できます");
    }
    const suspend = request.data?.suspend;
    if (typeof suspend !== "boolean") {
      throw new HttpsError("invalid-argument", "suspendが必要です");
    }
    const normalized = normalizeBulkTargets(
      request.data?.targetUserIds,
      request.auth.uid,
    );
    if (!normalized.ok) {
      throw new HttpsError("invalid-argument", normalized.reason);
    }
    const skipped: SkippedTarget[] = [...normalized.skipped];
    const changed: string[] = [];
    const writer = new ChunkedWriter();
    for (const id of normalized.ids) {
      const snapshot = await db.collection("users").doc(id).get();
      let isAdmin = false;
      if (suspend && snapshot.exists) {
        isAdmin = await getAuth()
          .getUser(id)
          .then((user) => user.customClaims?.admin === true)
          .catch(() => false);
      }
      const reason = classifyTarget(snapshot.data(), suspend, isAdmin);
      if (reason) {
        skipped.push({ id, reason });
        continue;
      }
      await writer.update(snapshot.ref, {
        accountStatus: suspend ? "suspended" : "active",
      });
      changed.push(id);
    }
    await writer.commit();
    if (suspend) {
      await Promise.all(
        changed.map((id) =>
          getAuth()
            .revokeRefreshTokens(id)
            .catch((error) => {
              logger.warn(`revokeRefreshTokensに失敗: ${id}`, error);
            }),
        ),
      );
    }
    if (changed.length > 0) {
      await writeAdminAuditLog({
        adminUid: request.auth.uid,
        action: suspend ? "suspend" : "unsuspend",
        targetUserIds: changed,
      });
    }
    logger.info(
      `アカウント一括${suspend ? "停止" : "解除"}: ${changed.length}件（対象外${skipped.length}件）`,
    );
    return { changed, skipped };
  },
);

/**
 * 管理者が住人のプロフィール（カード）を確認する操作を記録する（2026-10-10
 * 追加）。理由（通報対応/不正利用の調査/その他）を必須とし、記録に成功した
 * 時だけクライアントがカードを表示する。カードの実データ自体は`users`の
 * 読み取りルール上クライアントから直接読めるため、これは技術的な遮断では
 * なく、運営の閲覧を事後に検証できるようにするための記録。
 */
export const logAdminProfileView = onCall(
  { region: "asia-northeast1" },
  async (request) => {
    if (request.auth?.token.admin !== true) {
      throw new HttpsError("permission-denied", "管理者のみ実行できます");
    }
    const parsed = parseProfileViewRequest(request.data);
    if (!parsed.ok) {
      throw new HttpsError("invalid-argument", parsed.reason);
    }
    await db.collection("adminAuditLogs").add({
      adminUid: request.auth.uid,
      action: "viewProfile",
      targetUserIds: [parsed.targetUserId],
      reason: parsed.reason,
      note: parsed.note,
      createdAt: FieldValue.serverTimestamp(),
    });
  },
);

/** お便りの名前の既定値（`system/official`が未作成の時に使う）。 */
const OFFICIAL_DEFAULT_NAME = "お便り";

/** お便り1件の本文の最大文字数。 */
const ANNOUNCEMENT_MAX_LENGTH = 2000;

/**
 * 全住人（稼働中=accountStatus:'active'のアカウントのみ）にお便りを配信する
 * （管理者のみ）。お便りは住人（`users`）ではなく「そこにある物」として扱い
 * （2026-10-10変更、以前は固定UID`official-tayori`の住人から全員との一対へ
 * メッセージを書き込んでいた）、`announcements`に1件保存するだけで住人ごとの
 * 書き込みはしない。住人は設定>運営>お便りで`announcements`を読む。
 * 通知は、保存後に稼働中の住人のFCMトークンへ直接プッシュする（一対が無い
 * ため通知のディープリンクは付けない）。発信元の名前・アイコンは
 * `system/official`（管理画面の身だしなみタブで編集）を使う。
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
    if (message.length > ANNOUNCEMENT_MAX_LENGTH) {
      throw new HttpsError(
        "invalid-argument",
        `messageは${ANNOUNCEMENT_MAX_LENGTH}文字以内にしてください`,
      );
    }

    await db.collection("announcements").add({
      content: message,
      createdAt: FieldValue.serverTimestamp(),
      createdBy: request.auth.uid,
    });

    const official = (await db.doc("system/official").get()).data();
    const title: string =
      typeof official?.name === "string" && official.name
        ? official.name
        : OFFICIAL_DEFAULT_NAME;
    const iconUrl: string | null =
      typeof official?.iconUrl === "string" ? official.iconUrl : null;

    const usersSnapshot = await db
      .collection("users")
      .where("accountStatus", "==", "active")
      .get();
    const androidTokens: string[] = [];
    const webTokens: string[] = [];
    for (const userDoc of usersSnapshot.docs) {
      const tokens: FcmTokenEntry[] = userDoc.data().fcmTokens ?? [];
      for (const entry of tokens) {
        if (entry.platform === "android") androidTokens.push(entry.token);
        else if (entry.platform === "web") webTokens.push(entry.token);
      }
    }

    const body = message.length > 100 ? `${message.slice(0, 100)}…` : message;
    const messaging = getMessaging();
    // sendEachForMulticastは1回500トークンまで。
    for (let i = 0; i < androidTokens.length; i += 500) {
      await messaging.sendEachForMulticast({
        tokens: androidTokens.slice(i, i + 500),
        data: {
          title,
          body,
          iconUrl: iconUrl ?? "",
          previewUrl: "",
          isDm: "true",
          conversationId: "",
          roomId: "",
        },
        android: { priority: "high" },
      });
    }
    for (let i = 0; i < webTokens.length; i += 500) {
      await messaging.sendEachForMulticast({
        tokens: webTokens.slice(i, i + 500),
        webpush: {
          notification: { title, body, icon: iconUrl ?? undefined },
          data: { isDm: "true", conversationId: "", roomId: "" },
          fcmOptions: { link: "/" },
        },
      });
    }
    logger.info(`お便りを配信しました（対象${usersSnapshot.size}人）`);
    return { count: usersSnapshot.size };
  },
);

// ===== プッシュ通知（FCM、2026-08-31追加） =====
// 実装範囲はWeb + Androidのみ（iOS/macOSはApple Developer Program未加入、
// Windows/Linuxはfirebase_messagingが非対応のため対象外、CLAUDE.md・
// ユーザーとの相談で確定）。

type FcmTokenEntry = { token: string; platform: string };

/** [lib/models/app_user.dart]の`effectiveIconFor`/`effectiveNicknameFor`と
 * 同じ解決ロジック（工房カードの会話ごとの上書き→標準の工房カード→
 * 個別の蔵アイテム、の順）をTypeScript側に移植したもの。DMの通知タイトル・
 * アイコンは、送信者が自分自身にどう名乗っているか（送信者のusersドキュメント）
 * を参照する。 */
function resolveSenderIdentity(
  sender: FirebaseFirestore.DocumentData,
  conversationId: string,
): { name: string; iconUrl: string | null } {
  const overrideCardId: string | undefined =
    sender.conversationProfileCardId?.[conversationId] ??
    sender.activeProfileCardId ??
    undefined;
  const cards: Array<Record<string, unknown>> = sender.profileCards ?? [];
  const card = overrideCardId
    ? cards.find((c) => c.id === overrideCardId)
    : undefined;

  const nicknameId = (card ? card.nicknameId : sender.activeNicknameId) as
    | string
    | undefined;
  const nicknames: Array<Record<string, unknown>> = sender.nicknames ?? [];
  const nickname = nicknameId
    ? (nicknames.find((n) => n.id === nicknameId)?.text as string | undefined)
    : undefined;

  const iconId = (card ? card.iconId : sender.activeIconId) as
    | string
    | undefined;
  const icons: Array<Record<string, unknown>> = sender.icons ?? [];
  const iconUrl = iconId
    ? ((icons.find((i) => i.id === iconId)?.url as string | undefined) ??
      null)
    : null;

  return { name: nickname ?? (sender.rhingSeed as string) ?? "", iconUrl };
}

/** [lib/features/chat/chat_screen.dart]の`_replySnippetLabel`と同等の
 * contentType別プレビュー文言。スタンプ・動画のみプレビュー画像を返す。 */
function buildMessagePreview(
  message: FirebaseFirestore.DocumentData,
): { body: string; previewUrl: string | null } {
  switch (message.contentType) {
    case "text":
      return { body: String(message.content ?? "").slice(0, 80), previewUrl: null };
    case "sticker":
      return {
        body: "ぺったん",
        previewUrl: (message.stickerData?.stickerUrl as string) ?? null,
      };
    case "image":
      return { body: "[画像]", previewUrl: null };
    case "video":
      return {
        body: "[動画]",
        previewUrl: (message.fileMetadata?.thumbnailUrl as string) ?? null,
      };
    case "file":
      return {
        body: (message.fileMetadata?.fileName as string) ?? "[ファイル]",
        previewUrl: null,
      };
    default:
      return { body: "", previewUrl: null };
  }
}

/** `users/{recipientId}/conversationPrefs/{conversationId}`のミュート設定
 * （寄合単位の上書きがあればそちらを優先）を見て、通知を送るべきかを判定する。 */
async function isConversationMuted(
  recipientId: string,
  conversationId: string,
  roomId: string,
): Promise<boolean> {
  const prefsDoc = await db
    .doc(`users/${recipientId}/conversationPrefs/${conversationId}`)
    .get();
  if (!prefsDoc.exists) return false;
  const data = prefsDoc.data()!;
  const override = data.roomNotificationOverrides?.[roomId];
  if (typeof override === "boolean") return override;
  return data.notificationsMuted === true;
}

async function sendMessageNotification(params: {
  isDm: boolean;
  conversationId: string;
  roomId: string;
  message: FirebaseFirestore.DocumentData;
}): Promise<void> {
  const { isDm, conversationId, roomId, message } = params;
  if (message.silent === true) return;
  if (message.contentType === "call" || message.contentType === "accountDeleted") {
    return;
  }

  const senderId: string = message.senderId;
  // Webhook由来の投稿（`botName`あり）は送信者の`users`ドキュメントを持たない
  // ため、送信者の取得を飛ばし、タイトルを広場名、本文に`{BOT名}: `を付ける
  // （2026-10-10追加）。
  const botName: string | null =
    typeof message.botName === "string" ? message.botName : null;
  let sender: FirebaseFirestore.DocumentData = {};
  if (botName === null) {
    const senderDoc = await db.doc(`users/${senderId}`).get();
    if (!senderDoc.exists) return;
    sender = senderDoc.data()!;
  }

  let recipientIds: string[];
  let title: string;
  let iconUrl: string | null;
  if (isDm) {
    const dmDoc = await db.doc(`directMessages/${conversationId}`).get();
    const participants: string[] = dmDoc.data()?.participants ?? [];
    recipientIds = participants.filter((id) => id !== senderId);
    const identity = resolveSenderIdentity(sender, conversationId);
    title = identity.name;
    iconUrl = identity.iconUrl;
  } else {
    const groupDoc = await db.doc(`groups/${conversationId}`).get();
    const memberIds: string[] = groupDoc.data()?.memberIds ?? [];
    recipientIds = memberIds.filter((id) => id !== senderId);
    const inviteDoc = await db.doc(`groupInvites/${conversationId}`).get();
    title =
      (inviteDoc.data()?.name as string) ??
      (groupDoc.data()?.name as string) ??
      "";
    iconUrl = (inviteDoc.data()?.iconUrl as string) ?? null;
  }
  if (recipientIds.length === 0) return;

  const preview = buildMessagePreview(message);
  const body = botName === null ? preview.body : `${botName}: ${preview.body}`;
  const previewUrl = preview.previewUrl;

  const androidTokens: string[] = [];
  const webTokens: string[] = [];
  for (const recipientId of recipientIds) {
    if (await isConversationMuted(recipientId, conversationId, roomId)) {
      continue;
    }
    const recipientDoc = await db.doc(`users/${recipientId}`).get();
    const tokens: FcmTokenEntry[] = recipientDoc.data()?.fcmTokens ?? [];
    for (const entry of tokens) {
      if (entry.platform === "android") androidTokens.push(entry.token);
      else if (entry.platform === "web") webTokens.push(entry.token);
    }
  }
  if (androidTokens.length === 0 && webTokens.length === 0) return;

  const messaging = getMessaging();
  if (androidTokens.length > 0) {
    // Androidの通知アイコン/画像はローカルアセットかバイト列でしか渡せない
    // ため、data-onlyで送りクライアント（lib/push_notifications.dart）側で
    // flutter_local_notificationsを使い自前でリッチ通知を組み立てる。
    await messaging.sendEachForMulticast({
      tokens: androidTokens,
      data: {
        title,
        body,
        iconUrl: iconUrl ?? "",
        previewUrl: previewUrl ?? "",
        // 通知タップで該当の語らいまで開くためのディープリンク情報
        // （2026-09-02追加、lib/push_notifications.dart参照）。
        isDm: String(isDm),
        conversationId,
        roomId,
      },
      android: { priority: "high" },
    });
  }
  if (webTokens.length > 0) {
    await messaging.sendEachForMulticast({
      tokens: webTokens,
      webpush: {
        notification: {
          title,
          body,
          icon: iconUrl ?? undefined,
          image: previewUrl ?? undefined,
        },
        // 通知タップで該当の語らいまで開くためのディープリンク情報
        // （2026-09-02追加、web/firebase-messaging-sw.js参照）。FCMが
        // webpush通知を自動表示する際、この`data`が表示されたNotificationの
        // `.data`としてnotificationclickハンドラから参照できる。
        data: {
          isDm: String(isDm),
          conversationId,
          roomId,
        },
        fcmOptions: { link: "/" },
      },
    });
  }
}

/**
 * 語らい一覧（TalksTab）の未読件数バッジ用に、送信者以外の参加者/メンバー
 * 全員の`users/{recipientId}/conversationPrefs/{conversationId}.unreadCount`
 * を+1する（2026-09-02追加）。既読になった側のリセットはクライアントが
 * 自分の`conversationPrefs`へ直接書き込む
 * （`ConversationPrefsRepository.setLastRead`）ため、ここでは加算のみ行う。
 * 通知の送信条件（`silent`・`call`/`accountDeleted`除外）とは独立して、
 * 実際に届いた全メッセージを対象にする。
 */
async function incrementUnreadCounts(params: {
  isDm: boolean;
  conversationId: string;
  roomId: string;
  message: FirebaseFirestore.DocumentData;
}): Promise<void> {
  const { isDm, conversationId, roomId, message } = params;
  const senderId: string = message.senderId;

  let recipientIds: string[];
  if (isDm) {
    const dmDoc = await db.doc(`directMessages/${conversationId}`).get();
    const participants: string[] = dmDoc.data()?.participants ?? [];
    recipientIds = participants.filter((id) => id !== senderId);
  } else {
    const groupDoc = await db.doc(`groups/${conversationId}`).get();
    const memberIds: string[] = groupDoc.data()?.memberIds ?? [];
    recipientIds = memberIds.filter((id) => id !== senderId);
  }
  if (recipientIds.length === 0) return;

  const batch = db.batch();
  for (const recipientId of recipientIds) {
    const ref = db.doc(
      `users/${recipientId}/conversationPrefs/${conversationId}`,
    );
    // 寄合ごとの未読数（`unreadByRoom`）も加算する（2026-10-04追加）。
    // ドット記法はset+mergeではネストとして扱われないため、ネストMapで書く。
    batch.set(
      ref,
      {
        unreadCount: FieldValue.increment(1),
        unreadByRoom: { [roomId]: FieldValue.increment(1) },
      },
      { merge: true },
    );
  }
  await batch.commit();
}

export const onDmMessageCreated = onDocumentCreated(
  {
    document: "directMessages/{dmId}/rooms/{roomId}/messages/{messageId}",
    region: "asia-northeast1",
  },
  async (event) => {
    const message = event.data?.data();
    if (!message) return;
    await Promise.all([
      sendMessageNotification({
        isDm: true,
        conversationId: event.params.dmId,
        roomId: event.params.roomId,
        message,
      }),
      incrementUnreadCounts({
        isDm: true,
        conversationId: event.params.dmId,
        roomId: event.params.roomId,
        message,
      }),
    ]);
  },
);

// ---------------------------------------------------------------------------
// 受信Webhook（寄合へ外部から投稿できる、bot・API段階1、2026-10-10追加）
//
// `groups/{groupId}/webhooks/{webhookId}`に投稿先の寄合・トークンのハッシュ等を
// 保存する。クライアントは`manageBots`権限者のみ読み取りでき、書き込みは常に
// この関数群（Admin SDK）経由。純粋なロジックは`webhook.ts`（単体テスト済み）。
// ---------------------------------------------------------------------------

/** Webhookを作成する。トークン入りのURLは**この応答でしか返さない**。 */
export const createWebhook = onCall(
  { region: "asia-northeast1" },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "ログインが必要です");
    const { groupId, roomId, name } = (request.data ?? {}) as Record<
      string,
      unknown
    >;
    if (typeof groupId !== "string" || typeof roomId !== "string") {
      throw new HttpsError("invalid-argument", "groupIdとroomIdが必要です");
    }
    const webhookName = normalizeWebhookName(name);
    if (webhookName === null) {
      throw new HttpsError("invalid-argument", "名前が正しくありません");
    }

    const groupRef = db.doc(`groups/${groupId}`);
    const groupDoc = await groupRef.get();
    const group = groupDoc.data();
    if (
      !groupDoc.exists ||
      !(group?.memberIds as string[] | undefined)?.includes(uid) ||
      !canManageBots(group, uid)
    ) {
      throw new HttpsError("permission-denied", "権限がありません");
    }
    const roomDoc = await groupRef.collection("rooms").doc(roomId).get();
    if (!roomDoc.exists) {
      throw new HttpsError("not-found", "寄合が見つかりません");
    }
    const existing = await groupRef.collection("webhooks").count().get();
    if (existing.data().count >= WEBHOOK_MAX_PER_GROUP) {
      throw new HttpsError(
        "failed-precondition",
        `Webhookは1つの広場に${WEBHOOK_MAX_PER_GROUP}件までです`,
      );
    }

    const token = generateWebhookToken();
    const webhookRef = groupRef.collection("webhooks").doc();
    await webhookRef.set({
      name: webhookName,
      roomId,
      createdBy: uid,
      createdAt: FieldValue.serverTimestamp(),
      tokenHash: hashWebhookToken(token),
      lastUsedAt: null,
      rateWindowStartMs: null,
      rateCount: 0,
    });
    const projectId = process.env.GCLOUD_PROJECT ?? "daidai-rhing";
    return {
      webhookId: webhookRef.id,
      url: `https://asia-northeast1-${projectId}.cloudfunctions.net/postWebhookMessage/${groupId}/${webhookRef.id}/${token}`,
    };
  },
);

/** Webhookを削除する（URLは即座に無効になる）。 */
export const deleteWebhook = onCall(
  { region: "asia-northeast1" },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "ログインが必要です");
    const { groupId, webhookId } = (request.data ?? {}) as Record<
      string,
      unknown
    >;
    if (typeof groupId !== "string" || typeof webhookId !== "string") {
      throw new HttpsError("invalid-argument", "groupIdとwebhookIdが必要です");
    }
    const groupDoc = await db.doc(`groups/${groupId}`).get();
    const group = groupDoc.data();
    if (
      !groupDoc.exists ||
      !(group?.memberIds as string[] | undefined)?.includes(uid) ||
      !canManageBots(group, uid)
    ) {
      throw new HttpsError("permission-denied", "権限がありません");
    }
    await db.doc(`groups/${groupId}/webhooks/${webhookId}`).delete();
    return { ok: true };
  },
);

/**
 * Webhook URLへのPOSTで、寄合にメッセージを投稿する。
 * `POST …/postWebhookMessage/{groupId}/{webhookId}/{token}`、本文
 * `{ "content": string, "silent"?: boolean }`。トークン不一致・Webhook不在・
 * 寄合不在はすべて同じ404（存在を悟らせない）。
 */
export const postWebhookMessage = onRequest(
  { region: "asia-northeast1" },
  async (req, res) => {
    const notFound = () => {
      res.status(404).json({ error: "not_found" });
    };
    if (req.method !== "POST") {
      res.set("Allow", "POST");
      res.status(405).json({ error: "method_not_allowed" });
      return;
    }
    const parsed = parseWebhookPath(req.path);
    if (!parsed) return notFound();
    const { groupId, webhookId, token } = parsed;

    const webhookRef = db.doc(`groups/${groupId}/webhooks/${webhookId}`);
    const webhookSnap = await webhookRef.get();
    const webhook = webhookSnap.data();
    if (!webhook || !verifyWebhookToken(token, webhook.tokenHash)) {
      return notFound();
    }

    const contentLength = Number(req.headers["content-length"] ?? 0);
    if (contentLength > WEBHOOK_BODY_MAX_BYTES) {
      res.status(413).json({ error: "payload_too_large" });
      return;
    }
    if (!req.is("application/json")) {
      res.status(415).json({ error: "unsupported_media_type" });
      return;
    }
    const payload = parseWebhookPayload(req.body);
    if (!payload.ok) {
      res.status(400).json({ error: "invalid_payload", message: payload.reason });
      return;
    }

    const roomRef = db.doc(`groups/${groupId}/rooms/${webhook.roomId}`);
    const roomSnap = await roomRef.get();
    if (!roomSnap.exists) return notFound();

    // レート制限（1 Webhookあたり固定窓。トランザクションで窓カウントを更新）。
    const allowed = await db.runTransaction(async (tx) => {
      const fresh = (await tx.get(webhookRef)).data();
      if (!fresh) return false;
      const decision = nextRateState(
        {
          windowStartMs: (fresh.rateWindowStartMs as number | null) ?? null,
          count: (fresh.rateCount as number | undefined) ?? 0,
        },
        Date.now(),
      );
      if (decision.allowed) {
        tx.update(webhookRef, {
          rateWindowStartMs: decision.windowStartMs,
          rateCount: decision.count,
          lastUsedAt: FieldValue.serverTimestamp(),
        });
      }
      return decision.allowed;
    });
    if (!allowed) {
      res.set("Retry-After", "60");
      res.status(429).json({ error: "rate_limited" });
      return;
    }

    const messageRef = roomRef.collection("messages").doc();
    const content = payload.content;
    const singleLine = content.replace(/\n/g, " ");
    const preview =
      singleLine.length <= 80 ? singleLine : `${singleLine.slice(0, 80)}…`;
    const batch = db.batch();
    batch.set(messageRef, {
      conversationId: roomRef.id,
      conversationType: "room",
      senderId: webhookSenderId(webhookId),
      senderRhingSeed: null,
      botName: webhook.name as string,
      content,
      contentType: "text",
      sentAt: FieldValue.serverTimestamp(),
      hiddenFor: [],
      readBy: [],
      isSpam: false,
      silent: payload.silent,
      replyToMessageId: null,
      replyToSenderId: null,
      replyToSenderRhingSeed: null,
      replyToSnippet: null,
      editedAt: null,
      reactions: {},
    });
    batch.update(roomRef, { lastMessageAt: FieldValue.serverTimestamp() });
    batch.update(db.doc(`groups/${groupId}`), {
      lastMessageAt: FieldValue.serverTimestamp(),
      lastMessageSenderId: webhookSenderId(webhookId),
      lastMessageContentType: "text",
      lastMessagePreview: preview,
    });
    await batch.commit();
    res.status(200).json({ ok: true, messageId: messageRef.id });
  },
);

export const onGroupMessageCreated = onDocumentCreated(
  {
    document: "groups/{groupId}/rooms/{roomId}/messages/{messageId}",
    region: "asia-northeast1",
  },
  async (event) => {
    const message = event.data?.data();
    if (!message) return;
    await Promise.all([
      sendMessageNotification({
        isDm: false,
        conversationId: event.params.groupId,
        roomId: event.params.roomId,
        message,
      }),
      incrementUnreadCounts({
        isDm: false,
        conversationId: event.params.groupId,
        roomId: event.params.roomId,
        message,
      }),
    ]);
  },
);

/** 投票（poll）の回答が作成・更新・削除された際、親の投票ドキュメントの
 * `responseCount`/`optionVoteCounts`（選択肢ごとの得票数）を、`responses`
 * サブコレクションを都度全件読み直して絶対値で計算し直す（2026-09-06追加、
 * 同日に差分加算（`before`/`after`のキー差分をFieldValue.incrementで
 * 積み上げる方式）から変更）。差分加算方式は、Cloud Functionsのトリガー
 * 配信が"at least once"を保証しない（まれに配信されない・重複することが
 * ある）ことに弱く、1回でも取りこぼすとその後ずっと数値がズレたままになる
 * 不具合が実際に発生した（新規デプロイ直後の最初の書き込みイベントが
 * 反映されず、選択肢の得票数が負になった）。都度全件再集計する方式なら、
 * 個々のトリガー発火が欠落・重複しても、その時点で発火したトリガーが
 * 必ず正しい絶対値へ収束させる（自己修復的）。想定回答者数（DM・小規模な
 * 広場が主対象）では全件読み直しのコストも無視できる範囲。匿名投票では
 * `responses`サブコレクションの読み取りを本人のみに絞っているため、この
 * 非正規化カウンタがAdmin SDK経由で正確な集計値を全員に安全に見せる
 * 唯一の手段になる。 */
async function recomputePollAggregates(
  topCollection: "directMessages" | "groups",
  parentId: string,
  roomId: string,
  pollId: string,
) {
  const pollRef = db.doc(
    `${topCollection}/${parentId}/rooms/${roomId}/polls/${pollId}`,
  );
  const responsesSnapshot = await pollRef.collection("responses").get();

  let responseCount = 0;
  const optionVoteCounts: Record<string, number> = {};
  for (const doc of responsesSnapshot.docs) {
    // 不正な重複キー（selectedOptionKeysに同じ選択肢が複数回含まれる場合）に
    // よる二重加算を防ぐため必ずSet化する。
    const selectedKeys = new Set<string>(
      (doc.data().selectedOptionKeys ?? []) as string[],
    );
    if (selectedKeys.size === 0) continue;
    responseCount += 1;
    for (const key of selectedKeys) {
      optionVoteCounts[key] = (optionVoteCounts[key] ?? 0) + 1;
    }
  }

  await pollRef.update({ responseCount, optionVoteCounts });
}

export const onDmPollResponseWritten = onDocumentWritten(
  {
    document:
      "directMessages/{dmId}/rooms/{roomId}/polls/{pollId}/responses/{uid}",
    region: "asia-northeast1",
  },
  async (event) => {
    await recomputePollAggregates(
      "directMessages",
      event.params.dmId,
      event.params.roomId,
      event.params.pollId,
    );
  },
);

export const onGroupPollResponseWritten = onDocumentWritten(
  {
    document: "groups/{groupId}/rooms/{roomId}/polls/{pollId}/responses/{uid}",
    region: "asia-northeast1",
  },
  async (event) => {
    await recomputePollAggregates(
      "groups",
      event.params.groupId,
      event.params.roomId,
      event.params.pollId,
    );
  },
);

/** [conversationId]（dmId・groupId）直下の各roomを順に確認し、[messageId]の
 * メッセージが実際にどのroomにあるかを特定する（Storageの保存パスは
 * `dmFiles/{dmId}/{messageId}.ext`のようにroomをまたいでフラットなため、
 * アップロードイベント単体からはroomIdが分からない。会話1件あたりの
 * room数は少数のため、全room走査で十分）。 */
async function findMessageRef(
  topCollection: "directMessages" | "groups",
  parentId: string,
  messageId: string,
): Promise<FirebaseFirestore.DocumentReference | null> {
  const roomsSnap = await db
    .collection(topCollection)
    .doc(parentId)
    .collection("rooms")
    .get();
  for (const roomDoc of roomsSnap.docs) {
    const messageRef = roomDoc.ref.collection("messages").doc(messageId);
    const messageSnap = await messageRef.get();
    if (messageSnap.exists) return messageRef;
  }
  return null;
}

/**
 * 動画メッセージのアップロード完了時に1フレーム抽出してサムネイル画像を
 * 生成し、Storageへ保存した上でメッセージの`fileMetadata.thumbnailUrl`に
 * 記録する（プッシュ通知のプレビュー画像用、2026-08-31追加）。
 * `lib/utils/attachment_upload.dart`が保存する`dmFiles/{dmId}/{messageId}.ext`・
 * `groupFiles/{groupId}/{messageId}.ext`という規約に依存している。
 */
export const generateVideoThumbnail = onObjectFinalized(
  { region: "asia-northeast1", memory: "1GiB", timeoutSeconds: 120 },
  async (event) => {
    const filePath = event.data.name;
    const contentType = event.data.contentType;
    if (!filePath || !contentType?.startsWith("video/")) return;
    if (!filePath.startsWith("dmFiles/") && !filePath.startsWith("groupFiles/")) {
      return;
    }
    if (filePath.includes("_thumb.")) return; // 生成物自身の再帰防止

    const segments = filePath.split("/");
    if (segments.length !== 3) return;
    const [prefix, parentId, fileName] = segments;
    const messageId = fileName.replace(/\.[^.]+$/, "");

    const bucket = getStorage().bucket(event.data.bucket);
    const tmpVideoPath = path.join(
      os.tmpdir(),
      `${messageId}-src${path.extname(fileName)}`,
    );
    const tmpThumbFileName = `${messageId}-thumb.jpg`;
    const tmpThumbPath = path.join(os.tmpdir(), tmpThumbFileName);

    await bucket.file(filePath).download({ destination: tmpVideoPath });
    await new Promise<void>((resolve, reject) => {
      ffmpeg(tmpVideoPath)
        .on("end", () => resolve())
        .on("error", (err: Error) => reject(err))
        .screenshots({
          count: 1,
          timestamps: ["1"],
          filename: tmpThumbFileName,
          folder: os.tmpdir(),
        });
    });

    const thumbStoragePath = `${prefix}/${parentId}/${messageId}_thumb.jpg`;
    const downloadToken = randomUUID();
    await bucket.upload(tmpThumbPath, {
      destination: thumbStoragePath,
      metadata: {
        contentType: "image/jpeg",
        metadata: { firebaseStorageDownloadTokens: downloadToken },
      },
    });
    fs.unlinkSync(tmpVideoPath);
    fs.unlinkSync(tmpThumbPath);

    // Admin SDKにはクライアントSDKのgetDownloadURL()相当が無いため、既存の
    // 添付ファイルURL（attachment_upload.dart:84）と同じ「トークン付き
    // ダウンロードURL」形式を自前で組み立てる（GCSのgetSignedUrlは使わない。
    // ルールを経由せず読める既存添付ファイルURLと形式を揃えるため）。
    const encodedPath = encodeURIComponent(thumbStoragePath);
    const thumbnailUrl =
      `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/` +
      `${encodedPath}?alt=media&token=${downloadToken}`;

    const topCollection = prefix === "dmFiles" ? "directMessages" : "groups";
    const messageRef = await findMessageRef(topCollection, parentId, messageId);
    if (!messageRef) {
      logger.warn(`動画サムネイル生成: メッセージが見つかりません (${filePath})`);
      return;
    }
    await messageRef.update({ "fileMetadata.thumbnailUrl": thumbnailUrl });
  },
);

// ============================================================
// スパム対策（技術仕様書8章「スパム対策・仲間システム」、2026-09-07実装）。
// 8.4のCAPTCHA（bot的挙動時の要求）は新規の外部サービス契約が必要なため
// 今回は対象外（日記.mdにフォローアップとして記録）。それ以外の8.3
// （3層検知）・8.4（段階的停止）をここに実装する。
// ============================================================

/** 2人のuserIdから決定的なペアidを作る（firestore.rulesのpairId()・
 * DartモデルのidFor()と同じ規則）。 */
function pairId(a: string, b: string): string {
  return [a, b].sort().join("_");
}

const FRIEND_REQUEST_NEW_ACCOUNT_AGE_DAYS = 7;
const FRIEND_REQUEST_RATE_LIMIT_NEW = { perHour: 5, perDay: 10 };
const FRIEND_REQUEST_RATE_LIMIT_NORMAL = { perHour: 30, perDay: 100 };
const FRIEND_REQUEST_RATE_LIMIT_LOW_APPROVAL_PER_HOUR = 5;
const FRIEND_REQUEST_LOW_APPROVAL_MIN_SENT = 10;
const FRIEND_REQUEST_LOW_APPROVAL_THRESHOLD = 0.3;
const DUPLICATE_BROADCAST_WINDOW_MINUTES = 10;
const DUPLICATE_BROADCAST_MIN_RECIPIENTS = 5;

/**
 * 友達申請の送信（技術仕様書8.3レイヤー1「友達リクエスト段階」・
 * レイヤー2「未承認者へのメッセージ」）。クライアントの直接Firestore
 * 書き込みでは時間窓ごとのレート制限を安全に強制できないため、
 * `suspendUserAccount`等と同じくAdmin SDK経由のcallableに寄せている
 * （`lib/repositories/friend_repository.dart`の`FirestoreFriendRepository.
 * sendRequest`参照）。新規送信／相互申請の即時承認／拒否後の再送信という
 * 分岐ロジック自体は、このcallableへ移行する前のクライアント側実装と
 * 同じ内容をここに移植した。
 */
export const sendFriendRequest = onCall(
  { region: "asia-northeast1" },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }
    const fromUserId = request.data?.fromUserId;
    // rhingId→rhingSeedへの改名に伴う移行期間シム（2026-09-23追加）。
    // クライアントの動作確認が済んだら`request.data?.fromRhingId`/
    // `request.data?.toRhingId`のフォールバックを削除すること。
    const fromRhingSeed = request.data?.fromRhingSeed ?? request.data?.fromRhingId;
    const toUserId = request.data?.toUserId;
    const toRhingSeed = request.data?.toRhingSeed ?? request.data?.toRhingId;
    const rawMessage = request.data?.message;
    if (
      typeof fromUserId !== "string" ||
      typeof fromRhingSeed !== "string" ||
      typeof toUserId !== "string" ||
      typeof toRhingSeed !== "string"
    ) {
      throw new HttpsError("invalid-argument", "パラメータが不正です");
    }
    if (fromUserId !== uid) {
      throw new HttpsError("permission-denied", "本人としてのみ送信できます");
    }
    if (toUserId === fromUserId) {
      throw new HttpsError("invalid-argument", "自分自身には送信できません");
    }
    const message: string | null =
      typeof rawMessage === "string" && rawMessage.trim() ? rawMessage.trim() : null;
    if (message !== null && message.length > 100) {
      throw new HttpsError(
        "invalid-argument",
        "メッセージは100文字以内で入力してください",
      );
    }

    const now = Timestamp.now();
    const attempts = db.collection("friendRequestAttempts");

    const [hourSnapshot, daySnapshot, fromUserDoc, sentSnapshot, acceptedSnapshot] =
      await Promise.all([
        attempts
          .where("fromUserId", "==", fromUserId)
          .where(
            "createdAt",
            ">=",
            Timestamp.fromMillis(now.toMillis() - 60 * 60 * 1000),
          )
          .get(),
        attempts
          .where("fromUserId", "==", fromUserId)
          .where(
            "createdAt",
            ">=",
            Timestamp.fromMillis(now.toMillis() - 24 * 60 * 60 * 1000),
          )
          .get(),
        db.collection("users").doc(fromUserId).get(),
        db.collection("friendRequests").where("fromUserId", "==", fromUserId).get(),
        db
          .collection("friendRequests")
          .where("fromUserId", "==", fromUserId)
          .where("status", "==", "accepted")
          .get(),
      ]);

    // 新規アカウント（技術仕様書8.3の「新規アカウント」）の判定基準は
    // 明記が無いため、作成から7日未満を新規とみなす（後で調整可能な定数）。
    const createdAt = fromUserDoc.data()?.createdAt as
      | FirebaseFirestore.Timestamp
      | undefined;
    const isNewAccount =
      !createdAt ||
      now.toMillis() - createdAt.toMillis() <
        FRIEND_REQUEST_NEW_ACCOUNT_AGE_DAYS * 24 * 60 * 60 * 1000;

    // 承認率30%未満の判定は、送信した友達申請の累計（送信数・承認数）に対して行う。
    const totalSent = sentSnapshot.size;
    const totalAccepted = acceptedSnapshot.size;
    const isLowApproval =
      totalSent >= FRIEND_REQUEST_LOW_APPROVAL_MIN_SENT &&
      totalAccepted / totalSent < FRIEND_REQUEST_LOW_APPROVAL_THRESHOLD;

    const baseLimit = isNewAccount
      ? FRIEND_REQUEST_RATE_LIMIT_NEW
      : FRIEND_REQUEST_RATE_LIMIT_NORMAL;
    const hourLimit = isLowApproval
      ? Math.min(baseLimit.perHour, FRIEND_REQUEST_RATE_LIMIT_LOW_APPROVAL_PER_HOUR)
      : baseLimit.perHour;

    if (hourSnapshot.size >= hourLimit || daySnapshot.size >= baseLimit.perDay) {
      await db.collection("spamViolations").add({
        userId: fromUserId,
        kind: "rateLimitExceeded",
        createdAt: FieldValue.serverTimestamp(),
      });
      throw new HttpsError(
        "resource-exhausted",
        "友達申請の送信回数が上限に達しました。しばらく時間をおいてから再度お試しください。",
      );
    }

    // レイヤー2: 同一内容メッセージを短時間に複数人へ送るスパムパターンの検知。
    // メッセージ内容自体はサーバーに保存せずハッシュのみ比較する。
    let messageHash: string | null = null;
    if (message) {
      messageHash = createHash("sha256").update(message).digest("hex");
      const windowStart = Timestamp.fromMillis(
        now.toMillis() - DUPLICATE_BROADCAST_WINDOW_MINUTES * 60 * 1000,
      );
      const duplicateSnapshot = await attempts
        .where("fromUserId", "==", fromUserId)
        .where("messageHash", "==", messageHash)
        .where("createdAt", ">=", windowStart)
        .get();
      const distinctRecipients = new Set(
        duplicateSnapshot.docs.map((doc) => doc.data().toUserId as string),
      );
      distinctRecipients.add(toUserId);
      if (distinctRecipients.size >= DUPLICATE_BROADCAST_MIN_RECIPIENTS) {
        await db.collection("spamViolations").add({
          userId: fromUserId,
          kind: "duplicateBroadcast",
          createdAt: FieldValue.serverTimestamp(),
        });
        throw new HttpsError(
          "resource-exhausted",
          "同一内容のメッセージを短時間に複数人へ送ろうとしたため、送信を拒否しました。",
        );
      }
    }

    // ここまで到達した試行はレート制限のカウント対象として記録する
    // （実際に友達申請が成立したかどうかに関わらず、送信操作そのものを数える）。
    await attempts.add({
      fromUserId,
      toUserId,
      messageHash,
      createdAt: FieldValue.serverTimestamp(),
    });

    // 相互承認時のfriends/directMessages/dmRoom作成
    // （`FirestoreFriendRepository.respond`と同じ内容のAdmin SDK版）。
    const createFriendship = async (
      userAId: string,
      userARhingSeed: string,
      userBId: string,
      userBRhingSeed: string,
    ): Promise<void> => {
      const dmId = pairId(userAId, userBId);
      const dmRef = db.collection("directMessages").doc(dmId);
      const roomRef = dmRef.collection("rooms").doc();
      const batch = db.batch();
      batch.set(
        db.collection("users").doc(userAId).collection("friends").doc(userBId),
        { friendRhingSeed: userBRhingSeed, addedAt: FieldValue.serverTimestamp() },
      );
      batch.set(
        db.collection("users").doc(userBId).collection("friends").doc(userAId),
        { friendRhingSeed: userARhingSeed, addedAt: FieldValue.serverTimestamp() },
      );
      batch.set(dmRef, {
        participants: [userAId, userBId],
        participantRhingSeeds: { [userAId]: userARhingSeed, [userBId]: userBRhingSeed },
        readReceiptsEnabled: true,
        roomsEnabled: false,
      });
      batch.set(roomRef, {
        dmId,
        name: "メイン",
        participants: [userAId, userBId],
        createdAt: FieldValue.serverTimestamp(),
        pinnedMessageIds: [],
      });
      await batch.commit();
    };

    const requestId = pairId(fromUserId, toUserId);
    const ref = db.collection("friendRequests").doc(requestId);
    const doc = await ref.get();

    if (!doc.exists) {
      await ref.set({
        fromUserId,
        fromRhingSeed,
        toUserId,
        toRhingSeed,
        status: "pending",
        message,
        createdAt: FieldValue.serverTimestamp(),
        respondedAt: null,
      });
      return;
    }

    const existing = doc.data()!;
    if (existing.status === "accepted") {
      // statusがacceptedのままでも、絶縁等で実際のfriendsサブコレクションが
      // 既に削除されている場合がある。実際にまだ友達なら何もしない。
      const stillFriends = (
        await db
          .collection("users")
          .doc(fromUserId)
          .collection("friends")
          .doc(toUserId)
          .get()
      ).exists;
      if (stillFriends) return;
    } else if (existing.status === "pending") {
      if (existing.fromUserId === fromUserId) {
        return; // 既に自分から送信済み・返答待ち
      }
      // 相手からの申請が届いていた＝相互に追加しようとした。その場で承認扱いにする。
      await ref.update({
        status: "accepted",
        respondedAt: FieldValue.serverTimestamp(),
      });
      await createFriendship(
        existing.fromUserId,
        existing.fromRhingSeed,
        existing.toUserId,
        existing.toRhingSeed,
      );
      return;
    }

    // declined、またはaccepted済みだが実際は友達ではない場合: 再申請として上書きする。
    await ref.set({
      fromUserId,
      fromRhingSeed,
      toUserId,
      toRhingSeed,
      status: "pending",
      message,
      createdAt: FieldValue.serverTimestamp(),
      respondedAt: null,
    });
  },
);

const SUSPENSION_LOOKBACK_DAYS = 30;
// 技術仕様書8.4「違反種別×回数」の具体的な回数配分までは明記が無いため、
// 直近30日の累計違反件数を根拠にした簡易な段階分けとする
// （1件目は記録のみ、2件目=12時間、3件目=7日間、4件目以降=永久停止）。
const SUSPENSION_TIER_HOURS: (number | null)[] = [12, 24 * 7, null];

/**
 * `spamViolations`（レイヤー1・2はサーバー側、レイヤー3はクライアントの
 * 「送信を取りやめた」報告）が作成されるたびに、直近30日の累計件数を集計し
 * 段階的にアカウントを自動停止する（技術仕様書8.4）。運営による手動停止
 * （`suspendUserAccount`、`autoSuspendedUntil`を持たない）とは独立させ、
 * 手動停止中のアカウントは上書きしない（CLAUDE.md記載の既存方針）。
 * CAPTCHA（bot的挙動時の要求）は新規の外部サービス契約が必要なため未実装。
 */
export const onSpamViolationCreated = onDocumentCreated(
  { document: "spamViolations/{violationId}", region: "asia-northeast1" },
  async (event) => {
    const violation = event.data?.data();
    const userId = violation?.userId as string | undefined;
    if (!userId) return;

    const lookback = Timestamp.fromMillis(
      Date.now() - SUSPENSION_LOOKBACK_DAYS * 24 * 60 * 60 * 1000,
    );
    const recentSnapshot = await db
      .collection("spamViolations")
      .where("userId", "==", userId)
      .where("createdAt", ">=", lookback)
      .get();
    const count = recentSnapshot.size;

    const tierIndex = count - 2;
    if (tierIndex < 0) return; // 1件目は様子見（記録のみ）

    const userRef = db.collection("users").doc(userId);
    const userDoc = await userRef.get();
    if (
      userDoc.data()?.accountStatus === "suspended" &&
      userDoc.data()?.autoSuspendedUntil == null
    ) {
      // 運営による手動停止中は自動停止で上書きしない。
      return;
    }

    const hours =
      SUSPENSION_TIER_HOURS[Math.min(tierIndex, SUSPENSION_TIER_HOURS.length - 1)];
    const autoSuspendedUntil =
      hours === null ? null : Timestamp.fromMillis(Date.now() + hours * 60 * 60 * 1000);

    await userRef.update({
      accountStatus: "suspended",
      autoSuspendedUntil,
    });
    await getAuth()
      .revokeRefreshTokens(userId)
      .catch((error) => {
        logger.warn(`revokeRefreshTokensに失敗: ${userId}`, error);
      });
    logger.info(
      `スパム違反によりアカウントを自動停止: ${userId} ` +
        `(直近${SUSPENSION_LOOKBACK_DAYS}日で${count}件, ` +
        `${hours === null ? "永久" : `${hours}時間`})`,
    );
  },
);

/**
 * 技術仕様書8.4の期限付き自動停止（[onSpamViolationCreated]が設定する
 * `autoSuspendedUntil`）が経過したアカウントを1時間ごとに検出し、
 * 自動的に解除する。`autoSuspendedUntil`を持たない運営の手動停止は
 * 対象外（Firestoreのクエリ仕様上、フィールドがnullのドキュメントは
 * 不等号比較にマッチしないため自然に除外される）。
 */
export const reactivateExpiredSuspensions = onSchedule(
  { schedule: "0 * * * *", timeZone: "Asia/Tokyo", region: "asia-northeast1" },
  async () => {
    const now = Timestamp.now();
    const snapshot = await db
      .collection("users")
      .where("accountStatus", "==", "suspended")
      .where("autoSuspendedUntil", "<=", now)
      .get();
    if (snapshot.empty) return;

    const writer = new ChunkedWriter();
    for (const doc of snapshot.docs) {
      await writer.update(doc.ref, {
        accountStatus: "active",
        autoSuspendedUntil: null,
      });
    }
    await writer.commit();
    logger.info(`期限付き自動停止を解除: ${snapshot.size}件`);
  },
);

/**
 * 招待リンク（`/invite/:rhingSeed`・`/join/:groupId`）のOGP画像を生成して返す
 * （2026-10-10、Vercelの`api/og-image`から移植）。Cloudflare Pages側のWorkerが
 * `/api/og-image`をここへ中継する。誰でも呼べる公開エンドポイントで、
 * 読むのは公開プレビュー（`userInvites`/`groupInvites`）のみ。
 */
export const ogImage = onRequest(
  { region: "asia-northeast1", memory: "1GiB", timeoutSeconds: 60, cors: true },
  async (req, res) => {
    if (req.method !== "GET") {
      res.status(405).send("GET only");
      return;
    }
    const type = typeof req.query.type === "string" ? req.query.type : null;
    const id = typeof req.query.id === "string" ? req.query.id : null;
    if ((type !== "user" && type !== "group") || !id || !/^[\w.\-]{1,128}$/.test(id)) {
      res.status(400).send("invalid parameters");
      return;
    }
    try {
      const png = await renderOgImage(type, id);
      res.set("Content-Type", "image/png");
      res.set("Cache-Control", "public, max-age=300");
      res.status(200).send(png);
    } catch (err) {
      logger.error("OGP画像の生成に失敗しました:", err);
      res.status(500).send("failed to render");
    }
  },
);
