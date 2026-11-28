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
import { getMessaging, type MulticastMessage } from "firebase-admin/messaging";
import { getStorage } from "firebase-admin/storage";
import {
  type AuthenticatorTransportFuture,
  generateAuthenticationOptions,
  generateRegistrationOptions,
  verifyAuthenticationResponse,
  verifyRegistrationResponse,
} from "@simplewebauthn/server";
import { logger } from "firebase-functions";
import { defineSecret, defineString } from "firebase-functions/params";
import {
  onDocumentCreated,
  onDocumentDeleted,
  onDocumentUpdated,
  onDocumentWritten,
} from "firebase-functions/v2/firestore";
import {
  type CallableRequest,
  HttpsError,
  onCall,
  onRequest,
} from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { onObjectFinalized } from "firebase-functions/v2/storage";
import { spawn } from "node:child_process";
import ffmpeg from "fluent-ffmpeg";
import { path as ffmpegPath } from "@ffmpeg-installer/ffmpeg";
import Stripe from "stripe";
import { parseKiwamiReference } from "./kiwamiReference";
import {
  ACTIVE_STATUSES,
  SubmitError,
  type SubmissionStore,
  submitThemePack as submitThemePackBody,
} from "./themePackSubmit";
import {
  type AccountDeletionStore,
  deleteThemePackData,
} from "./themePackAccountDeletion";
import { cleanupExpiredDraftFiles, type DraftFileStore } from "./draftFileCleanup";
import {
  type OrphanCleanupStore,
  cleanupOrphanSubmissionAssets,
  recentFailures,
  FAILURE_LIMIT,
} from "./themePackAbuse";
import {
  type ReviewStore,
  ReviewError,
  approveThemePack as approveThemePackBody,
  rejectThemePack as rejectThemePackBody,
  suspendThemePack as suspendThemePackBody,
} from "./themePackReview";
import {
  type OwnershipStore,
  OwnershipError,
  acquireThemePack as acquireThemePackBody,
  uninstallThemePack as uninstallThemePackBody,
  withdrawThemePack as withdrawThemePackBody,
} from "./themePackOwnership";
import {
  CallRecordResult,
  dmCallRecordResult,
  groupCallRecordResult,
} from "./callRecordResult";
import {
  type PackDeletionStatus,
  type Validated,
  canTransition,
  deletionRequestId,
  packDeletionNoticeText,
  stickerDeletionNoticeText,
  validateDeleteAt,
  validateDeletionText,
  validateStickerRemoval,
} from "./packDeletion";
import {
  REPORT_CONTEXT_AFTER,
  REPORT_CONTEXT_BEFORE,
  type EvidenceMessage,
  isOverDailyLimit,
  parseReportInput,
  parseResolution,
  reportTargetKey,
  toEvidenceMessage,
} from "./reports";
import { parseRoleUpdates } from "./stickerRoles";
import {
  SWITCH_MAX_SESSIONS_PER_USER,
  SWITCH_SESSION_SCAN_LIMIT,
  SWITCH_SESSION_TTL_MS,
  pickSessionsToEvict,
  type AliveSession,
  SWITCH_TICKET_TTL_MS,
  decideSessionOwner,
  evaluateRedeem,
  generateSecret,
  hashSecret,
  isKiwamiPlan,
  verifySecret,
} from "./switchSession";
import { aliasExpiresAtMs, evaluateSeedChange } from "./rhingSeedChange";
import {
  kMaxPlaybackSourceSeconds,
  kPlaybackOutputOptions,
  kPlaybackTranscodeBudgetMs,
  kPlaybackScaleFilter,
  needsPlaybackVersion,
  parseFfmpegInfo,
  playbackStoragePath,
} from "./playbackVideo";

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
export {
  botApi,
  createBot,
  deleteBot,
  rotateBotToken,
} from "./botFunctions";
import {
  type SkippedTarget,
  classifyTarget,
  normalizeBulkTargets,
  parseProfileViewRequest,
} from "./adminUsers";
import { recallPayload, recallRecipients } from "./messageRecall";
import {
  RETENTION_EXPIRE_LIMIT,
  conversationFromDocPath,
  deleteMessageAttachments,
  expireMessageAttachments,
  hasExpirableAttachment,
  legacyExpiresAtMs,
  retentionExpiresAtMs,
  type ChatMessageData,
  type RetentionStore,
} from "./retention";
import { renderOgImage } from "./ogImage";
import { checkRequest, checkRespond, ISSUED_QR_TTL_MS } from "./qrLoginIssued";
import { parseAllowedUrl, resolveReferer, resolveUserAgent } from "./urlFetchRelay";
import { resolveMentionRecipients } from "./mentions";
import { excludeBlockers } from "./block";
import { type FcmTokenEntry, mergeFcmTokenEntries } from "./fcmTokens";
import {
  SCHEDULED_BATCH_LIMIT,
  isFailedScheduledExpired,
  scheduledSendFailure,
} from "./scheduledMessages";
import { severanceNotifyTarget } from "./severanceNotify";
import { filterTurnIceServers } from "./turnCredentials";
import {
  groupCallNotificationBody,
  groupCallRecipients,
} from "./groupCallNotify";
import { decideJoin, newMemberPermissions } from "./joinGroup";
import {
  isNewPendingRequest,
  resolveJoinRequestRecipients,
} from "./joinRequestNotify";
import {
  friendRequestBody,
  resolveFriendRequestRecipient,
} from "./friendRequestNotify";
import {
  withSenderName,
  withSentTime,
} from "./notificationFormat";

if (ffmpegPath) ffmpeg.setFfmpegPath(ffmpegPath);

initializeApp();

const db = getFirestore();

// Stripe連携用のシークレット（値はFirebase CLIの
// `firebase functions:secrets:set STRIPE_SECRET_KEY` 等で個別に設定する。
// コード上には値を持たない）。
const stripeSecretKey = defineSecret("STRIPE_SECRET_KEY");
const stripeWebhookSecret = defineSecret("STRIPE_WEBHOOK_SECRET");
// 通話のTURN（中継サーバー、Cloudflare Realtime TURN）のキー。通話で別回線同士が
// 直接つながらない時の中継に使う（2026-10-21）。どちらも
// `firebase functions:secrets:set TURN_KEY_ID` / `TURN_KEY_API_TOKEN`で個別に設定する。
const turnKeyId = defineSecret("TURN_KEY_ID");
const turnKeyApiToken = defineSecret("TURN_KEY_API_TOKEN");

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
    // 停止中のアカウントが、削除で停止を逃れないようにする（2026-11-21、Strixの指摘）。
    // 運営が停止を解除するか、管理者が削除する。
    if (userDoc.data()?.accountStatus === "suspended") {
      throw new HttpsError(
        "failed-precondition",
        "アカウントが停止されている間は削除できません",
      );
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

/**
 * Rhing Seedを変更する（設定＞アカウント、2026-11-07）。`users`のルールは
 * `rhingSeed`の更新を禁止している（予約語の迂回・他人のSeedへの書き換え防止）
 * ため、Admin SDKのこの関数だけが変更できる。判定は[evaluateSeedChange]。
 *
 * - 変更は100日に1回。最終変更日時は`users/{uid}/private/seedChange`の1件だけ
 *   （過去のSeedの履歴は持たない）。
 * - 変更前のSeedは`rhingSeedAliases/{旧seed}`（uid・期限のみ）として60日間予約し、
 *   旧招待リンクを新Seedへ転送する。期限が切れたら[purgeExpiredSeedAliases]が消す。
 */
export const changeRhingSeed = onCall(
  { region: "asia-northeast1" },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }
    const requested = request.data?.newSeed;
    if (typeof requested !== "string") {
      throw new HttpsError("invalid-argument", "newSeedが必要です");
    }
    const userRef = db.collection("users").doc(uid);
    const changeRef = userRef.collection("private").doc("seedChange");

    const newSeed = await db.runTransaction(async (tx) => {
      const userDoc = await tx.get(userRef);
      if (!userDoc.exists) {
        throw new HttpsError("not-found", "ユーザーが見つかりません");
      }
      const currentSeed = String(userDoc.data()?.rhingSeed ?? "");
      const normalized = requested.trim().toLowerCase();
      const [changeDoc, takenSnap, aliasDoc] = await Promise.all([
        tx.get(changeRef),
        tx.get(
          db
            .collection("users")
            .where("rhingSeed", "==", normalized)
            .limit(2),
        ),
        tx.get(db.collection("rhingSeedAliases").doc(normalized)),
      ]);
      const changedAt = changeDoc.data()?.changedAt as Timestamp | undefined;
      const aliasData = aliasDoc.data();
      const nowMs = Date.now();
      const result = evaluateSeedChange({
        newSeed: requested,
        currentSeed,
        lastChangedAtMs: changedAt ? changedAt.toMillis() : null,
        nowMs,
        takenByOther: takenSnap.docs.some((d) => d.id !== uid),
        alias: aliasData
          ? {
              uid: String(aliasData.uid),
              expiresAtMs: (aliasData.expiresAt as Timestamp).toMillis(),
            }
          : null,
        uid,
      });
      if (!result.ok) {
        throw new HttpsError(result.error.code, result.error.message);
      }

      const oldInviteRef = db.collection("userInvites").doc(currentSeed);
      const oldInvite = await tx.get(oldInviteRef);

      tx.update(userRef, { rhingSeed: result.newSeed });
      tx.set(changeRef, { changedAt: Timestamp.fromMillis(nowMs) });
      if (currentSeed) {
        tx.set(db.collection("rhingSeedAliases").doc(currentSeed), {
          uid,
          expiresAt: Timestamp.fromMillis(aliasExpiresAtMs(nowMs)),
        });
        tx.delete(oldInviteRef);
      }
      if (result.restoringOwnAlias) {
        tx.delete(db.collection("rhingSeedAliases").doc(result.newSeed));
      }
      if (oldInvite.exists) {
        tx.set(db.collection("userInvites").doc(result.newSeed), oldInvite.data()!);
      }
      return result.newSeed;
    });

    logger.info(`Rhing Seed変更: ${uid}`);
    return { rhingSeed: newSeed };
  },
);

/** 期限（60日）が切れた旧Seedの予約を毎日削除する。旧→新の対応を長く残さない
 * ための掃除（Firestore TTLポリシーを設定した場合は不要になる）。 */
export const purgeExpiredSeedAliases = onSchedule(
  { schedule: "30 0 * * *", timeZone: "Asia/Tokyo", region: "asia-northeast1" },
  async () => {
    const snapshot = await db
      .collection("rhingSeedAliases")
      .where("expiresAt", "<=", Timestamp.now())
      .get();
    const writer = new ChunkedWriter();
    for (const doc of snapshot.docs) {
      await writer.delete(doc.ref);
    }
    await writer.commit();
  },
);

async function deleteAccount(
  userId: string,
  userData: FirebaseFirestore.DocumentData,
): Promise<void> {
  const rhingSeed: string | undefined = userData.rhingSeed;

  // 意匠を全て削除する（2026-11-26、規約第9条）。取得した人の表示は、標準へ戻る
  // （お知らせは送らない）。失敗は握りつぶさず投げる。`users/{uid}`が残るため、
  // `processAccountDeletions`が翌日に再実行する（各段は冪等）。
  await deleteThemePackData(themePackAccountDeletionStore, userId);

  const writer = new ChunkedWriter();

  // 変更前のSeedの予約（対応表）も残さない。
  const aliasSnap = await db
    .collection("rhingSeedAliases")
    .where("uid", "==", userId)
    .get();
  for (const doc of aliasSnap.docs) {
    await writer.delete(doc.ref);
  }

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
  // 居住地（自己申告、本人のみ読めるサブコレクション）も削除する。
  await deleteSubcollection(
    db.collection("users").doc(userId).collection("private"),
    writer,
  );
  // 複数アカウントの切り替え用の合言葉（2026-11-11）も残さない。
  await deleteSubcollection(
    db.collection("users").doc(userId).collection("switchSessions"),
    writer,
  );
  // サウンドボードの効果音（個人保存、2026-11-17）。Storageのファイルは、他の個人保存の
  // 素材（`userSounds`など）と同じく、ここでは消していない。
  await deleteSubcollection(
    db.collection("users").doc(userId).collection("soundboardSounds"),
    writer,
  );
  // 登録済みパスキーの公開鍵（2026-11-18、これまで残っていた）。Firestoreは親の
  // ドキュメントを消してもサブコレクションを消さない。
  await deleteSubcollection(
    db.collection("users").doc(userId).collection("passkeyCredentials"),
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
 * 複数アカウントの切り替え（2026-11-11、極みの特典）。端末に保存した「切り替え用の合言葉」を
 * サーバーが検証してカスタムトークンを発行する。判定は`switchSession.ts`（純関数）。
 * 設計は`文書/直近/複数アカウント.md`。保存先は`users/{uid}/switchSessions/{sessionId}`と
 * `switchTickets/{ticketHash}`（どちらもクライアントから読み書き不可、Admin SDKのみ）。
 */

/** 別のアカウントを追加するための、10分・1回限りのチケット（極みのアカウントだけが発行できる）。 */
export const createSwitchTicket = onCall(
  { region: "asia-northeast1" },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "ログインが必要です");
    const userSnap = await db.collection("users").doc(uid).get();
    if (!isKiwamiPlan(userSnap.data())) {
      throw new HttpsError(
        "failed-precondition",
        "アカウントを追加するには、極みの契約が必要です",
      );
    }
    const ticket = generateSecret();
    const nowMs = Date.now();
    const expiresAtMs = nowMs + SWITCH_TICKET_TTL_MS;
    await db.collection("switchTickets").doc(hashSecret(ticket)).set({
      ownerUid: uid,
      createdAtMs: nowMs,
      expiresAtMs,
    });
    return { ticket, expiresAtMs };
  },
);

/**
 * 今ログインしているアカウントの、切り替え用の合言葉を作る。極みのアカウントは自分で作れ、
 * それ以外は[ticket]（極みのアカウントが発行）が要る。合言葉は一度だけ返し、サーバーには
 * ハッシュだけを保存する。
 */
export const createSwitchSession = onCall(
  { region: "asia-northeast1" },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "ログインが必要です");
    const ticket = request.data?.ticket;
    const userRef = db.collection("users").doc(uid);
    const sessionsRef = userRef.collection("switchSessions");
    const sessionRef = sessionsRef.doc(randomUUID());
    const secret = generateSecret();
    const nowMs = Date.now();

    await db.runTransaction(async (tx) => {
      const userSnap = await tx.get(userRef);
      const callerIsKiwami = isKiwamiPlan(userSnap.data());

      let ticketRef: FirebaseFirestore.DocumentReference | undefined;
      let ticketData: FirebaseFirestore.DocumentData | undefined;
      let ticketOwnerIsKiwami = false;
      if (!callerIsKiwami && typeof ticket === "string" && ticket.length > 0) {
        ticketRef = db.collection("switchTickets").doc(hashSecret(ticket));
        ticketData = (await tx.get(ticketRef)).data();
        if (ticketData && typeof ticketData.ownerUid === "string") {
          const ownerSnap = await tx.get(
            db.collection("users").doc(ticketData.ownerUid),
          );
          ticketOwnerIsKiwami = isKiwamiPlan(ownerSnap.data());
        }
      }

      const decision = decideSessionOwner({
        callerUid: uid,
        callerIsKiwami,
        ticket: ticketData,
        ticketOwnerIsKiwami,
        nowMs,
      });
      if (!decision.ok) {
        throw new HttpsError(
          decision.code as "failed-precondition",
          decision.message,
        );
      }

      // 失効・期限切れのセッションは掃除する。残りが上限に達していても断らず、最後に使ったのが
      // 古いものから外して空ける（使われなくなった合言葉が溜まって追加が止まるのを防ぐ、2026-11-24）。
      const existing = await tx.get(
        sessionsRef.orderBy("createdAtMs").limit(SWITCH_SESSION_SCAN_LIMIT),
      );
      const aliveSessions: AliveSession[] = [];
      for (const doc of existing.docs) {
        const data = doc.data();
        const alive =
          data.revoked !== true &&
          typeof data.expiresAtMs === "number" &&
          data.expiresAtMs >= nowMs;
        if (alive) {
          const lastUsed = data.lastUsedAt;
          aliveSessions.push({
            id: doc.id,
            lastUsedAtMs:
              typeof lastUsed?.toMillis === "function"
                ? lastUsed.toMillis()
                : typeof data.createdAtMs === "number"
                  ? data.createdAtMs
                  : 0,
          });
        } else {
          tx.delete(doc.ref);
        }
      }
      for (const id of pickSessionsToEvict(
        aliveSessions,
        SWITCH_MAX_SESSIONS_PER_USER,
      )) {
        tx.delete(sessionsRef.doc(id));
      }

      // 使ったチケットは消す（1回限り）。
      if (ticketRef && !callerIsKiwami) tx.delete(ticketRef);
      tx.set(sessionRef, {
        secretHash: hashSecret(secret),
        kiwamiOwnerUid: decision.kiwamiOwnerUid,
        createdAtMs: nowMs,
        lastUsedAt: FieldValue.serverTimestamp(),
        expiresAtMs: nowMs + SWITCH_SESSION_TTL_MS,
        failures: 0,
        revoked: false,
      });
    });

    return { uid, sessionId: sessionRef.id, secret };
  },
);

/**
 * 保存した合言葉で、そのアカウントへ切り替える（未ログインでも呼べる）。成功すると
 * カスタムトークンを返す。極みの契約が切れていれば（所有者も本人も極みでなければ）
 * 「切り替えだけ止める」。合言葉は使っても変わらず、期限だけが延びる（複数のタブで
 * 同時に使っても壊れないように、更新はしない）。
 */
export const redeemSwitchSession = onCall(
  { region: "asia-northeast1" },
  async (request) => {
    const { uid, sessionId, secret } = request.data ?? {};
    if (
      typeof uid !== "string" ||
      typeof sessionId !== "string" ||
      typeof secret !== "string" ||
      !uid ||
      !sessionId ||
      !secret
    ) {
      throw new HttpsError("invalid-argument", "uid・sessionId・secretが必要です");
    }
    const userRef = db.collection("users").doc(uid);
    const sessionRef = userRef.collection("switchSessions").doc(sessionId);
    const nowMs = Date.now();

    // 失敗の回数は、拒否する時も書き込む必要があるため、例外は取引の外で投げる。
    const outcome = await db.runTransaction(async (tx) => {
      const session = (await tx.get(sessionRef)).data();
      const userData = (await tx.get(userRef)).data();
      const ownerUid = session?.kiwamiOwnerUid;
      let ownerData: FirebaseFirestore.DocumentData | undefined;
      if (typeof ownerUid === "string") {
        ownerData =
          ownerUid === uid
            ? userData
            : (await tx.get(db.collection("users").doc(ownerUid))).data();
      }
      const result = evaluateRedeem({
        session,
        secret,
        nowMs,
        targetUser: userData,
        ownerUser: ownerData,
      });
      if (result.kind === "ok") {
        tx.update(sessionRef, {
          lastUsedAt: FieldValue.serverTimestamp(),
          expiresAtMs: nowMs + SWITCH_SESSION_TTL_MS,
          failures: 0,
        });
      } else if (result.kind === "badSecret") {
        tx.update(sessionRef, {
          failures: FieldValue.increment(1),
          ...(result.revoke ? { revoked: true } : {}),
        });
      }
      return result;
    });

    if (outcome.kind === "deny") {
      throw new HttpsError(outcome.code as "permission-denied", outcome.message);
    }
    if (outcome.kind === "badSecret") {
      throw new HttpsError(
        "permission-denied",
        "切り替えできません。もう一度ログインしてください",
      );
    }
    return { customToken: await getAuth().createCustomToken(uid) };
  },
);

/**
 * 保存したアカウントを取り外す（ログアウト・取り外し）。合言葉で本人の端末だと確かめて、
 * セッションを消す。別のアカウントにログインしている時でも呼べるよう、ログインは要らない。
 */
export const revokeSwitchSession = onCall(
  { region: "asia-northeast1" },
  async (request) => {
    const { uid, sessionId, secret } = request.data ?? {};
    if (
      typeof uid !== "string" ||
      typeof sessionId !== "string" ||
      typeof secret !== "string" ||
      !uid ||
      !sessionId ||
      !secret
    ) {
      throw new HttpsError("invalid-argument", "uid・sessionId・secretが必要です");
    }
    const ref = db
      .collection("users")
      .doc(uid)
      .collection("switchSessions")
      .doc(sessionId);
    const snap = await ref.get();
    if (!snap.exists) return { ok: true }; // 既に無ければ、取り外せたものとして扱う。
    if (!verifySecret(secret, snap.data()?.secretHash)) {
      throw new HttpsError("permission-denied", "取り外せません");
    }
    await ref.delete();
    return { ok: true };
  },
);

/**
 * ログイン済み端末がQRを表示し、ログインしたい端末が読み取る方式（2026-10-15）。
 * 流れ: createIssuedQrLoginSession（本人、QR表示）→ requestIssuedQrLogin（読み取った
 * 未ログイン端末）→ respondIssuedQrLogin（本人が許可/拒否）→ claimQrLoginSession
 * （既存、許可されたらカスタムトークンを受け取る）。許可を必須にして、QRを撮影・画面
 * 共有された第三者がそのままログインできないようにする。状態遷移の判定は
 * `qrLoginIssued.ts`。
 */
export const createIssuedQrLoginSession = onCall(
  { region: "asia-northeast1" },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }
    // 同時に有効なQRは1人1つ。古いissuedセッションは無効化（削除）する。
    const old = await db
      .collection("qrLoginSessions")
      .where("ownerUid", "==", uid)
      .get();
    await Promise.all(old.docs.map((doc) => doc.ref.delete()));
    const ref = await db.collection("qrLoginSessions").add({
      mode: "issued",
      ownerUid: uid,
      status: "pending",
      createdAt: FieldValue.serverTimestamp(),
    });
    return { sessionId: ref.id, ttlSeconds: ISSUED_QR_TTL_MS / 1000 };
  },
);

/** 未ログインの端末が、読み取ったQRのセッションにログインを要求する。 */
export const requestIssuedQrLogin = onCall(
  { region: "asia-northeast1" },
  async (request) => {
    const sessionId = request.data?.sessionId;
    if (typeof sessionId !== "string" || !sessionId) {
      throw new HttpsError("invalid-argument", "sessionIdが必要です");
    }
    const ref = db.collection("qrLoginSessions").doc(sessionId);
    await db.runTransaction(async (tx) => {
      const doc = await tx.get(ref);
      if (!doc.exists) {
        throw new HttpsError("not-found", "セッションが見つかりません");
      }
      const data = doc.data()!;
      const check = checkRequest(
        {
          mode: data.mode,
          status: data.status,
          createdAtMs: (data.createdAt as Timestamp | undefined)?.toMillis(),
        },
        Date.now(),
      );
      if (!check.ok) {
        throw new HttpsError(check.code as "failed-precondition", check.message);
      }
      tx.update(ref, { status: "requested", requestedAt: FieldValue.serverTimestamp() });
    });
  },
);

/** QRを表示したログイン済みの本人が、要求に許可/拒否を返す。 */
export const respondIssuedQrLogin = onCall(
  { region: "asia-northeast1" },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }
    const sessionId = request.data?.sessionId;
    const approve = request.data?.approve === true;
    if (typeof sessionId !== "string" || !sessionId) {
      throw new HttpsError("invalid-argument", "sessionIdが必要です");
    }
    const ref = db.collection("qrLoginSessions").doc(sessionId);
    await db.runTransaction(async (tx) => {
      const doc = await tx.get(ref);
      if (!doc.exists) {
        throw new HttpsError("not-found", "セッションが見つかりません");
      }
      const data = doc.data()!;
      const check = checkRespond(
        {
          mode: data.mode,
          status: data.status,
          ownerUid: data.ownerUid,
          createdAtMs: (data.createdAt as Timestamp | undefined)?.toMillis(),
        },
        uid,
        Date.now(),
      );
      if (!check.ok) {
        throw new HttpsError(check.code as "failed-precondition", check.message);
      }
      tx.update(
        ref,
        approve ? { status: "approved", approvedUid: uid } : { status: "denied" },
      );
    });
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
// 複数パスキー管理（2026-09-16追加）。
// 秘密の質問によるパスキー紛失時の復旧は、2026-11-18に廃止した（推測されやすく、
// バックアップコードも採用しないため）。パスキーを失った場合の復旧手段は、事前に
// 登録した別のパスキーか、後から連携するGoogle・Appleのログインのみで、どちらも
// 無ければ復旧できない（`文書/検討/バックアップコード.md`）。
// -----------------------------------------------------------------------

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

// ---------------------------------------------------------------------
// daidai横丁: ぺったんパッケージ関連のcallable（技術仕様書7.4・7.5参照、
// 2026-08-11追加）。stickerPacks/stickerPackReportsはfirestore.rulesで
// クライアントからの書き込みを一律禁止しているため、ぺったんの作成・編集・
// 通報はすべてここを経由する。HomePage-Rhing（daidai-yokochoセクション）
// からFirebase Client SDKのhttpsCallableで呼ばれる想定。
// ---------------------------------------------------------------------

const MIN_STICKERS_PER_PACK = 4;

// 有料ぺったんの出品・価格変更・購入を一時的に無効化するフラグ（2026-08-11追加）。
// 特定商取引法に基づく表記の整備・出品者への収益分配方式の決定・Stripe本番
// アカウントの審査が完了するまでは、無料（price===0）ぺったんの配布のみに限定する。
// 再開条件・チェックリストはDaiDai-技術仕様書.md 7.6節を参照。再開時はこの値を
// trueに変更するだけでよい（Stripe連携コード自体は動作確認済みのため削除しない）。
const PAID_PACKS_ENABLED = false;
const PAID_PACKS_DISABLED_MESSAGE =
  "現在、有料ぺったんには対応していません。無料（0円）ぺったんのみご利用いただけます。";

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
function assertValidStickers(value: unknown, minCount: number, creatorId: string): StickerInput[] {
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
    // 外部のURL・他人の画像を指せないよう、出品者自身のstickerPackAssets配下のURLだけを受ける
    // （2026-11-21、Strixの指摘。`replaceStickerImage`と同じ検証を作成・追加にも適用）
    if (!storagePathFromDownloadUrl(s.imageUrl, creatorId)) {
      throw new HttpsError(
        "invalid-argument",
        `stickers[${index}]のimageUrlが正しくありません`,
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
 * 出品者（DaiDaiアカウントを持つ誰でも即出品可、承認フローなし）が新規ぺったんを
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
    const stickers = assertValidStickers(request.data?.stickers, MIN_STICKERS_PER_PACK, uid);
    const category = typeof request.data?.category === "string" ? request.data.category : "";
    const tags: string[] = Array.isArray(request.data?.tags)
      ? request.data.tags.filter((t: unknown): t is string => typeof t === "string")
      : [];

    // ぺったんの「代表」にするぺったん（任意）。stickersに含まれるIDのときだけ保存する
    // （未設定・不正なときは保存せず、表示側は先頭のぺったんを代表にする）。
    const requestedCover = request.data?.coverStickerId;
    const coverStickerId =
      typeof requestedCover === "string" &&
      stickers.some((st) => st.stickerId === requestedCover)
        ? requestedCover
        : null;

    const ref = db.collection("stickerPacks").doc();
    await ref.set({
      creatorId: uid,
      name: name.trim(),
      price,
      stickers,
      category,
      tags,
      ...(coverStickerId ? { coverStickerId } : {}),
      salesCount: 0,
      // 現在このぺったんを所有しているユーザー数（購入付与Cloud Functionで+1、
      // アンインストール時のownedStickerPacks削除に連動して-1する想定の
      // 非正規化カウンタ、2026-08-11追加）。deleteStickerPackの削除可否判定に使う。
      // 購入付与・アンインストール連動の実処理はまだ未実装のため、現時点では
      // 常に0のまま（＝どのぺったんも削除可能）。
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
 * 意匠（コードを含まないデザインの設定ファイルと画像1枚）の提出（2026-11-26）。
 * HomePage（daidai横丁）が`themePackSubmissions/{uid}/{submissionId}/`へ置いたファイルを
 * サーバーで読み直して再検査し、`themePackSubmissions/{submissionId}`を`submitted`で作る。
 * 本体は`themePackSubmit.ts`（Firebase非依存）。ここは、Firestore・Storageの窓口と、
 * エラーの変換だけを持つ。承認・差し戻し等は別の関数（今回は無し）。
 * `themePackSubmissions`は、`stickerPacks`のような誰でも読めるコレクションとは別（未承認を混ぜない）。
 */
const themePackSubmissionStore: SubmissionStore = {
  async listFiles(prefix) {
    const [files] = await getStorage().bucket().getFiles({ prefix: `${prefix}/` });
    return files
      .filter((f) => !f.name.endsWith("/"))
      .map((f) => ({
        name: f.name.slice(prefix.length + 1),
        size: Number(f.metadata.size ?? 0),
        contentType: typeof f.metadata.contentType === "string" ? f.metadata.contentType : undefined,
      }));
  },
  async readFile(prefix, name) {
    const [buf] = await getStorage().bucket().file(`${prefix}/${name}`).download();
    return new Uint8Array(buf);
  },
  runTransaction(fn) {
    const col = db.collection("themePackSubmissions");
    return db.runTransaction((t) =>
      fn({
        async getSubmission(submissionId) {
          const snap = await t.get(col.doc(submissionId));
          if (!snap.exists) return null;
          const d = snap.data()!;
          return { creatorId: String(d.creatorId), packId: String(d.packId), version: Number(d.version) };
        },
        async countActive(creatorId) {
          const snap = await t.get(
            col.where("creatorId", "==", creatorId).where("status", "in", [...ACTIVE_STATUSES]).select(),
          );
          return snap.size;
        },
        async countSince(creatorId, sinceMillis) {
          // 状態は問わない（却下・取り下げも、投稿した回数として数える）。
          // `creatorId`と`createdAt`の複合インデックスが要る（firestore.indexes.json）
          const snap = await t.get(
            col.where("creatorId", "==", creatorId).where("createdAt", ">=", Timestamp.fromMillis(sinceMillis)).select(),
          );
          return snap.size;
        },
        async maxVersion(packId) {
          const snap = await t.get(col.where("packId", "==", packId).orderBy("version", "desc").limit(1));
          return snap.empty ? 0 : Number(snap.docs[0].data().version);
        },
        create(submissionId, record) {
          t.set(col.doc(submissionId), {
            packId: record.packId,
            creatorId: record.creatorId,
            version: record.version,
            status: "submitted",
            assetPath: record.assetPath,
            name: record.name,
            brightness: record.brightness,
            rightsAcceptedAt: FieldValue.serverTimestamp(),
            createdAt: FieldValue.serverTimestamp(),
          });
        },
      }),
    );
  },
  // 荒らし対策（2026-11-26）。どちらもサーバー専用の文書（firestore.rulesに許可が無く、既定で拒否）
  async isBlocked(uid) {
    return (await db.collection("themePackSubmissionBlocks").doc(uid).get()).exists;
  },
  async getFailures(uid) {
    const snap = await db.collection("themePackSubmitFailures").doc(uid).get();
    const raw = snap.data()?.failedAtMillis;
    return Array.isArray(raw) ? raw.filter((n): n is number => typeof n === "number") : [];
  },
  async recordFailure(uid, nowMillis) {
    const ref = db.collection("themePackSubmitFailures").doc(uid);
    await db.runTransaction(async (t) => {
      const snap = await t.get(ref);
      const raw = snap.data()?.failedAtMillis;
      const before = Array.isArray(raw) ? raw.filter((n): n is number => typeof n === "number") : [];
      const next = [...recentFailures(before, nowMillis), nowMillis].slice(-FAILURE_LIMIT);
      t.set(ref, { failedAtMillis: next });
    });
  },
};

export const submitThemePack = onCall(
  { region: "asia-northeast1" },
  async (request) => {
    let result;
    try {
      result = await submitThemePackBody(themePackSubmissionStore, {
        uid: request.auth?.uid,
        data: request.data,
      });
    } catch (e) {
      if (e instanceof SubmitError) throw new HttpsError(e.code, e.message);
      throw e;
    }
    // 初めての投稿のタイミングで、daidai横丁の公開プロフィールミラー（creatorProfiles）を
    // 作る（`createStickerPack`と同じ作法）。以後の変更は`syncCreatorProfile`が追随する。
    const userDoc = await db.collection("users").doc(request.auth!.uid).get();
    if (userDoc.exists) {
      await projectCreatorProfile(request.auth!.uid, userDoc.data()!);
    }
    return result;
  },
);

/**
 * アカウント削除で、意匠を全て削除する窓口（2026-11-26）。本体は
 * `themePackAccountDeletion.ts`（Firebase非依存）。`deleteAccount`から呼ぶ。
 */
async function deleteUserSubcollectionChunk(uid: string, name: string, limit: number): Promise<number> {
  const snap = await db.collection("users").doc(uid).collection(name).limit(limit).get();
  if (snap.empty) return 0;
  const batch = db.batch();
  for (const d of snap.docs) batch.delete(d.ref);
  await batch.commit();
  return snap.size;
}

const themePackAccountDeletionStore: AccountDeletionStore = {
  async listCreatorPackIds(uid) {
    const [subs, packs] = await Promise.all([
      db.collection("themePackSubmissions").where("creatorId", "==", uid).select("packId").get(),
      db.collection("themePacks").where("creatorId", "==", uid).select().get(),
    ]);
    const ids = new Set<string>();
    for (const d of subs.docs) {
      const id = d.data().packId;
      if (typeof id === "string") ids.add(id);
    }
    for (const d of packs.docs) ids.add(d.id);
    return [...ids];
  },
  async deleteOwnedRecords(packId, limit) {
    const snap = await db
      .collectionGroup("ownedThemePacks")
      .where("packId", "==", packId)
      .limit(limit)
      .get();
    if (snap.empty) return 0;
    const batch = db.batch();
    for (const d of snap.docs) batch.delete(d.ref);
    await batch.commit();
    return snap.size;
  },
  async deletePrefix(prefix) {
    await getStorage().bucket().deleteFiles({ prefix, force: true });
  },
  async deletePackDoc(packId) {
    await db.collection("themePacks").doc(packId).delete();
  },
  async deleteSubmissionDocs(uid, limit) {
    const snap = await db.collection("themePackSubmissions").where("creatorId", "==", uid).limit(limit).get();
    if (snap.empty) return 0;
    const batch = db.batch();
    for (const d of snap.docs) batch.delete(d.ref);
    await batch.commit();
    return snap.size;
  },
  async listOwnedPackIds(uid) {
    const snap = await db.collection("users").doc(uid).collection("ownedThemePacks").select().get();
    return snap.docs.map((d) => d.id);
  },
  async releaseOwnedPack(uid, packId) {
    const ownedRef = db.collection("users").doc(uid).collection("ownedThemePacks").doc(packId);
    const packRef = db.collection("themePacks").doc(packId);
    await db.runTransaction(async (t) => {
      const [owned, pack] = await Promise.all([t.get(ownedRef), t.get(packRef)]);
      if (!owned.exists) return; // 再実行で、二重に減らさない
      if (pack.exists) {
        t.update(packRef, { ownerCount: Math.max(0, Number(pack.data()?.ownerCount ?? 0) - 1) });
      }
      t.delete(ownedRef);
    });
  },
  async deleteFavoriteDesigns(uid, limit) {
    return deleteUserSubcollectionChunk(uid, "favoriteDesigns", limit);
  },
  async deleteCartDesigns(uid, limit) {
    return deleteUserSubcollectionChunk(uid, "cartDesigns", limit);
  },
  async deleteAbuseRecords(uid) {
    await Promise.all([
      db.collection("themePackSubmitFailures").doc(uid).delete(),
      db.collection("themePackSubmissionBlocks").doc(uid).delete(),
    ]);
  },
};

/**
 * 提出されないまま残った意匠の素材の掃除（2026-11-26）。HomePageは、素材を先に置いてから
 * `submitThemePack`を呼ぶ。提出されなかった素材（同じIDの`themePackSubmissions`が無い）を、
 * 最後の書き込みから24時間後に消す。置いた直後の素材と、文書が有る素材（承認・差し戻し・
 * 取り下げを含む）は消さない。1回に消す数は上限があり、残りは翌日に回す。
 */
const themePackOrphanStore: OrphanCleanupStore = {
  async listAssetDirs() {
    const [files] = await getStorage().bucket().getFiles({ prefix: "themePackSubmissions/" });
    const dirs = new Map<string, { prefix: string; submissionId: string; newestMillis: number }>();
    for (const f of files) {
      const parts = f.name.split("/");
      // themePackSubmissions/{uid}/{submissionId}/{file}
      if (parts.length !== 4 || !parts[1] || !parts[2] || !parts[3]) continue;
      const created = Date.parse(String(f.metadata.timeCreated ?? ""));
      if (!Number.isFinite(created)) continue;
      const prefix = `${parts[0]}/${parts[1]}/${parts[2]}`;
      const cur = dirs.get(prefix);
      if (cur) cur.newestMillis = Math.max(cur.newestMillis, created);
      else dirs.set(prefix, { prefix, submissionId: parts[2], newestMillis: created });
    }
    return [...dirs.values()];
  },
  async existingSubmissionIds(ids) {
    const found = new Set<string>();
    for (let i = 0; i < ids.length; i += 300) {
      const refs = ids.slice(i, i + 300).map((id) => db.collection("themePackSubmissions").doc(id));
      const snaps = await db.getAll(...refs);
      for (const s of snaps) if (s.exists) found.add(s.id);
    }
    return found;
  },
  async deleteDir(prefix) {
    await getStorage().bucket().deleteFiles({ prefix: `${prefix}/`, force: true });
  },
};

export const cleanupOrphanThemePackAssets = onSchedule(
  { schedule: "0 4 * * *", timeZone: "Asia/Tokyo", region: "asia-northeast1", timeoutSeconds: 540 },
  async () => {
    const { deleted, failed } = await cleanupOrphanSubmissionAssets(themePackOrphanStore, Date.now());
    logger.info(`提出されなかった意匠の素材を掃除: 削除${deleted.length}件、失敗${failed.length}件`);
    if (failed.length > 0) logger.warn("掃除に失敗した素材", failed);
  },
);

/**
 * 入力欄の下書きに添えたファイル（`draftFiles/`、2026-11-27）を、7日を過ぎたものから消す。
 * 送信・取り外しで消えずに残ったものの掃除。判断は`draftFileCleanup.ts`、ここはStorageの一覧と削除だけ。
 */
const draftFileStore: DraftFileStore = {
  async list() {
    const [files] = await getStorage().bucket().getFiles({ prefix: "draftFiles/" });
    return files.map((f) => ({
      name: f.name,
      createdMillis: Date.parse(String(f.metadata.timeCreated ?? "")),
    }));
  },
  async delete(name) {
    await getStorage().bucket().file(name).delete({ ignoreNotFound: true });
  },
};

export const cleanupExpiredDraftFilesDaily = onSchedule(
  { schedule: "30 4 * * *", timeZone: "Asia/Tokyo", region: "asia-northeast1", timeoutSeconds: 540 },
  async () => {
    const { deleted, failed } = await cleanupExpiredDraftFiles(draftFileStore, Date.now());
    logger.info(`期限を過ぎた下書きのファイルを掃除: 削除${deleted.length}件、失敗${failed.length}件`);
    if (failed.length > 0) logger.warn("掃除に失敗した下書きのファイル", failed);
  },
);

/**
 * 運営による、意匠の投稿の停止・解除（管理者のみ、2026-11-26）。荒らしの利用者の投稿を止める。
 * 保存先は、`users`の項目ではなく、サーバー専用の`themePackSubmissionBlocks/{uid}`。
 * `users`は全ログインユーザーが読めるため、停止の事実を公開しない。他の機能（メッセージ等）は止めない。
 */
export const setThemePackSubmissionBlocked = onCall(
  { region: "asia-northeast1" },
  async (request) => {
    assertAdmin(request);
    const targetUserId = request.data?.targetUserId;
    if (typeof targetUserId !== "string" || !targetUserId || targetUserId.includes("/")) {
      throw new HttpsError("invalid-argument", "targetUserIdが必要です");
    }
    const blocked = request.data?.blocked;
    if (typeof blocked !== "boolean") {
      throw new HttpsError("invalid-argument", "blockedが必要です");
    }
    const reasonRaw = request.data?.reason;
    const reason = typeof reasonRaw === "string" && reasonRaw.trim() ? reasonRaw.trim().slice(0, 200) : undefined;
    if (targetUserId === request.auth!.uid) {
      throw new HttpsError("invalid-argument", "自分自身は対象にできません");
    }
    if (!(await db.collection("users").doc(targetUserId).get()).exists) {
      throw new HttpsError("not-found", "住人が見つかりません");
    }
    const ref = db.collection("themePackSubmissionBlocks").doc(targetUserId);
    if (blocked) {
      const target = await getAuth().getUser(targetUserId).catch(() => null);
      if (target?.customClaims?.admin === true) {
        throw new HttpsError("failed-precondition", "管理者は対象にできません");
      }
      await ref.set({
        blockedAt: FieldValue.serverTimestamp(),
        blockedBy: request.auth!.uid,
        ...(reason ? { reason } : {}),
      });
    } else {
      await ref.delete();
    }
    await writeAdminAuditLog({
      adminUid: request.auth!.uid,
      action: blocked ? "blockThemePackSubmission" : "unblockThemePackSubmission",
      targetUserIds: [targetUserId],
      ...(reason ? { reason } : {}),
    });
    logger.info(`意匠の投稿を${blocked ? "停止" : "再開"}: ${targetUserId}`);
  },
);

/**
 * 意匠の審査結果（承認・差し戻し・配信停止、2026-11-26）。本体は`themePackReview.ts`
 * （Firebase非依存）。ここは、Firestore・Storageの窓口と、エラーの変換、管理者の確認、
 * 監査ログだけを持つ。公開用の`themePacks`は承認済みと配信停止後のものだけ（未承認を混ぜない）。
 * お知らせは`users/{uid}/notices`に書くだけで、FCMのプッシュは送らない。
 */
const themePackReviewStore: ReviewStore = {
  listFiles: (prefix) => themePackSubmissionStore.listFiles(prefix),
  readFile: (prefix, name) => themePackSubmissionStore.readFile(prefix, name),
  async copyFile(fromPrefix, toPrefix, name) {
    const bucket = getStorage().bucket();
    await bucket.file(`${fromPrefix}/${name}`).copy(bucket.file(`${toPrefix}/${name}`));
  },
  runTransaction(fn) {
    const subs = db.collection("themePackSubmissions");
    const packs = db.collection("themePacks");
    return db.runTransaction((t) => {
      // Firestoreのtransactionは、読み取りを全て済ませてから書く。書き込みは、
      // 最後にまとめて実行する（本体は、読み取りの後に書き込みの関数を呼ぶ）
      const writes: (() => void)[] = [];
      const result = fn({
        async getSubmission(id) {
          const snap = await t.get(subs.doc(id));
          if (!snap.exists) return null;
          const d = snap.data()!;
          return {
            creatorId: String(d.creatorId),
            packId: String(d.packId),
            version: Number(d.version),
            status: String(d.status),
            assetPath: String(d.assetPath),
            name: typeof d.name === "string" ? d.name : undefined,
            brightness: typeof d.brightness === "string" ? d.brightness : undefined,
          };
        },
        async getPublicPack(packId) {
          const snap = await t.get(packs.doc(packId));
          if (!snap.exists) return null;
          const d = snap.data()!;
          return {
            creatorId: String(d.creatorId),
            name: String(d.name),
            version: Number(d.version),
            status: String(d.status),
          };
        },
        async findSubmission(packId, version) {
          const snap = await t.get(
            subs.where("packId", "==", packId).where("version", "==", version).limit(1),
          );
          return snap.empty ? null : { id: snap.docs[0].id, status: String(snap.docs[0].data().status) };
        },
        updateSubmission(id, patch) {
          writes.push(() =>
            t.update(subs.doc(id), {
              ...patch,
              ...(patch.status !== undefined ? { decidedAt: FieldValue.serverTimestamp() } : {}),
            }),
          );
        },
        createPublicPack(packId, data) {
          writes.push(() =>
            t.set(packs.doc(packId), {
              ...data,
              status: "approved",
              price: 0,
              ownerCount: 0,
              createdAt: FieldValue.serverTimestamp(),
              approvedAt: FieldValue.serverTimestamp(),
            }),
          );
        },
        updatePublicPack(packId, data) {
          writes.push(() =>
            t.update(packs.doc(packId), {
              ...data,
              status: "approved",
              approvedAt: FieldValue.serverTimestamp(),
            }),
          );
        },
        suspendPublicPack(packId) {
          writes.push(() =>
            t.update(packs.doc(packId), { status: "suspended", suspendedAt: FieldValue.serverTimestamp() }),
          );
        },
        addNotice(uid, notice) {
          writes.push(() =>
            t.set(db.collection("users").doc(uid).collection("notices").doc(), {
              content: notice.content,
              kind: notice.kind,
              packId: notice.packId,
              createdAt: FieldValue.serverTimestamp(),
            }),
          );
        },
      });
      return result.then((value) => {
        for (const w of writes) w();
        return value;
      });
    });
  },
  async listOwnerUids(packId) {
    const snap = await db.collectionGroup("ownedThemePacks").where("packId", "==", packId).get();
    const uids: string[] = [];
    for (const doc of snap.docs) {
      const uid = doc.ref.parent.parent?.id;
      if (uid) uids.push(uid);
    }
    return uids;
  },
  async writeNoticeBatch(uids, notice) {
    const batch = db.batch();
    for (const uid of uids) {
      const col = db.collection("users").doc(uid).collection("notices");
      batch.set(notice.id ? col.doc(notice.id) : col.doc(), {
        content: notice.content,
        kind: notice.kind,
        packId: notice.packId,
        createdAt: FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  },
};

async function runThemePackReview<T>(fn: () => Promise<T>): Promise<T> {
  try {
    return await fn();
  } catch (e) {
    if (e instanceof ReviewError) throw new HttpsError(e.code, e.message);
    throw e;
  }
}

export const approveThemePack = onCall(
  { region: "asia-northeast1", memory: "512MiB" },
  async (request) => {
    assertAdmin(request);
    const adminUid = request.auth!.uid;
    const result = await runThemePackReview(() =>
      approveThemePackBody(themePackReviewStore, { adminUid, data: request.data }),
    );
    if (result.changed) {
      await writeAdminAuditLog({
        adminUid,
        action: "approveThemePack",
        targetUserIds: [result.creatorId],
        note: `packId=${result.packId} version=${result.version} submissionId=${result.submissionId}`,
      });
    }
    return {
      submissionId: result.submissionId,
      packId: result.packId,
      version: result.version,
      status: result.status,
    };
  },
);

export const rejectThemePack = onCall(
  { region: "asia-northeast1" },
  async (request) => {
    assertAdmin(request);
    const adminUid = request.auth!.uid;
    const result = await runThemePackReview(() =>
      rejectThemePackBody(themePackReviewStore, { adminUid, data: request.data }),
    );
    await writeAdminAuditLog({
      adminUid,
      action: "rejectThemePack",
      targetUserIds: [result.creatorId],
      reason: String(request.data.reason).trim(),
      note: `packId=${result.packId} submissionId=${result.submissionId}`,
    });
    return { submissionId: result.submissionId, status: result.status };
  },
);

export const suspendThemePack = onCall(
  { region: "asia-northeast1", timeoutSeconds: 300 },
  async (request) => {
    assertAdmin(request);
    const adminUid = request.auth!.uid;
    const result = await runThemePackReview(() =>
      suspendThemePackBody(themePackReviewStore, { adminUid, data: request.data }),
    );
    if (result.changed) {
      await writeAdminAuditLog({
        adminUid,
        action: "suspendThemePack",
        targetUserIds: [result.creatorId],
        reason: String(request.data.reason).trim(),
        note: `packId=${result.packId}`,
      });
    }
    return { packId: result.packId, status: result.status, notifiedOwners: result.notifiedOwners };
  },
);

/**
 * 意匠の取得・アンインストール・取り下げ（2026-11-26）。本体は`themePackOwnership.ts`
 * （Firebase非依存）。ここは、Firestoreの窓口と、エラーの変換だけを持つ。
 * 取得済みの記録は`users/{uid}/ownedThemePacks/{packId}`（ぺったんの`ownedStickerPacks`とは別）。
 * 本体は、読み取りを全て済ませてから書き込みを呼ぶので、窓口は直接`t`へ書いてよい。
 */
const themePackOwnershipStore: OwnershipStore = {
  runTransaction(fn) {
    const packs = db.collection("themePacks");
    const subs = db.collection("themePackSubmissions");
    const ownedRef = (uid: string, packId: string) =>
      db.collection("users").doc(uid).collection("ownedThemePacks").doc(packId);
    return db.runTransaction((t) =>
      fn({
        async getPack(packId) {
          const snap = await t.get(packs.doc(packId));
          if (!snap.exists) return null;
          const d = snap.data()!;
          return {
            creatorId: String(d.creatorId),
            version: Number(d.version),
            status: String(d.status),
            price: typeof d.price === "number" ? d.price : 0,
            ownerCount: typeof d.ownerCount === "number" ? d.ownerCount : 0,
          };
        },
        async hasOwned(uid, packId) {
          return (await t.get(ownedRef(uid, packId))).exists;
        },
        async findSubmission(packId, version) {
          const snap = await t.get(
            subs.where("packId", "==", packId).where("version", "==", version).limit(1),
          );
          return snap.empty ? null : { id: snap.docs[0].id, status: String(snap.docs[0].data().status) };
        },
        setOwned(uid, packId, version) {
          t.set(ownedRef(uid, packId), { packId, version, grantedAt: FieldValue.serverTimestamp() });
        },
        deleteOwned(uid, packId) {
          t.delete(ownedRef(uid, packId));
        },
        setOwnerCount(packId, count) {
          t.update(packs.doc(packId), { ownerCount: count });
        },
        setPackStatus(packId, status) {
          t.update(packs.doc(packId), { status, withdrawnAt: FieldValue.serverTimestamp() });
        },
        setSubmissionStatus(submissionId, status) {
          t.update(subs.doc(submissionId), { status, decidedAt: FieldValue.serverTimestamp() });
        },
      }),
    );
  },
};

async function runThemePackOwnership<T>(fn: () => Promise<T>): Promise<T> {
  try {
    return await fn();
  } catch (e) {
    if (e instanceof OwnershipError) throw new HttpsError(e.code, e.message);
    throw e;
  }
}

export const acquireThemePack = onCall(
  { region: "asia-northeast1" },
  (request) =>
    runThemePackOwnership(() =>
      acquireThemePackBody(
        themePackOwnershipStore,
        { uid: request.auth?.uid, data: request.data },
        { paidPacksEnabled: PAID_PACKS_ENABLED },
      ),
    ),
);

export const uninstallThemePack = onCall(
  { region: "asia-northeast1" },
  (request) =>
    runThemePackOwnership(() =>
      uninstallThemePackBody(themePackOwnershipStore, { uid: request.auth?.uid, data: request.data }),
    ),
);

export const withdrawThemePack = onCall(
  { region: "asia-northeast1" },
  async (request) => {
    // 返り値は、changedを除いた形（HomePageが使うのはpackIdとstatus）
    const { packId, status } = await runThemePackOwnership(() =>
      withdrawThemePackBody(themePackOwnershipStore, { uid: request.auth?.uid, data: request.data }),
    );
    return { packId, status };
  },
);

/**
 * 出品済みぺったんのname・price・coverStickerId（ぺったんの「代表」にするぺったん）を
 * 変更する。画像（stickers）はここでは変更できない（追加専用の方針、
 * addStickersToStickerPack参照）。
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
      throw new HttpsError("not-found", "ぺったんが見つかりません");
    }
    if (doc.data()?.creatorId !== uid) {
      throw new HttpsError("permission-denied", "自分が出品したぺったんのみ編集できます");
    }

    const update: {
      name?: string;
      price?: number;
      coverStickerId?: string;
      updatedAt?: FirebaseFirestore.FieldValue;
    } = {};
    if (request.data?.name !== undefined) {
      if (typeof request.data.name !== "string" || !request.data.name.trim()) {
        throw new HttpsError("invalid-argument", "nameが不正です");
      }
      update.name = request.data.name.trim();
    }
    if (request.data?.price !== undefined) {
      const newPrice = assertValidPrice(request.data.price);
      const currentPrice = typeof doc.data()?.price === "number" ? doc.data()!.price : 0;
      // 既に有料設定済みのぺったん（凍結前に作成されたもの）の価格を維持する
      // 更新までは塞がない。新たに有料へ変更する操作のみを拒否する。
      if (newPrice > 0 && newPrice !== currentPrice && !PAID_PACKS_ENABLED) {
        throw new HttpsError("failed-precondition", PAID_PACKS_DISABLED_MESSAGE);
      }
      update.price = newPrice;
    }
    if (request.data?.coverStickerId !== undefined) {
      const coverStickerId = request.data.coverStickerId;
      const existing = Array.isArray(doc.data()?.stickers)
        ? (doc.data()!.stickers as { stickerId?: string }[])
        : [];
      if (
        typeof coverStickerId !== "string" ||
        !existing.some((st) => st.stickerId === coverStickerId)
      ) {
        throw new HttpsError(
          "invalid-argument",
          "coverStickerIdはこのぺったんの画像のIDである必要があります",
        );
      }
      update.coverStickerId = coverStickerId;
    }
    if (Object.keys(update).length === 0) {
      throw new HttpsError("invalid-argument", "name・price・coverStickerIdのいずれかが必要です");
    }
    update.updatedAt = FieldValue.serverTimestamp();
    await ref.update(update);
  },
);

/**
 * 出品済みぺったんに画像を追加する。技術仕様書7.5節の方針により、この関数は追加専用。
 * 差し替えは`replaceStickerImage`（運営の許可は不要、stickerIdは変わらない）、
 * 削除は申請制（`requestStickerPackDeletion`にstickerIdを付ける、2026-11-17）。
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
    // ぺったん全体の下限4件はcreateStickerPack側で保証済みのため、
    // 追加時は1件以上あればよい。
    const stickers = assertValidStickers(request.data?.stickers, 1, uid);

    const ref = db.collection("stickerPacks").doc(packId);
    const doc = await ref.get();
    if (!doc.exists) {
      throw new HttpsError("not-found", "ぺったんが見つかりません");
    }
    if (doc.data()?.creatorId !== uid) {
      throw new HttpsError("permission-denied", "自分が出品したぺったんのみ編集できます");
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
 * ぺったんの通報を記録する（v1は記録のみ、Rhing運営がFirebase console等で
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
      throw new HttpsError("not-found", "ぺったんが見つかりません");
    }
    await db.collection("stickerPackReports").add({
      packId,
      reporterUid: uid,
      reason: reason.trim().slice(0, 1000),
      createdAt: FieldValue.serverTimestamp(),
    });
  },
);

/**
 * Firebase Storageのダウンロード URL から、[creatorId]自身の`stickerPackAssets/`配下の
 * オブジェクトパスだけを取り出す（それ以外は null）。`imageUrl`はクライアントが自由に
 * 設定できる為、ホスト・バケット・パスを検証しないと、Admin SDKでバケット内の任意の
 * オブジェクト（他人のアイコン・添付）を削除できてしまう（2026-11-16、Strixの指摘）。
 */
function storagePathFromDownloadUrl(url: string, creatorId: string): string | null {
  let parsed: URL;
  try {
    parsed = new URL(url);
  } catch {
    return null;
  }
  if (parsed.protocol !== "https:" || parsed.hostname !== "firebasestorage.googleapis.com") {
    return null;
  }
  const match = parsed.pathname.match(/^\/v0\/b\/([^/]+)\/o\/(.+)$/);
  if (!match || match[1] !== getStorage().bucket().name) return null;
  let objectPath: string;
  try {
    objectPath = decodeURIComponent(match[2]);
  } catch {
    return null;
  }
  if (
    !objectPath.startsWith(`stickerPackAssets/${creatorId}/`) ||
    objectPath.split("/").includes("..")
  ) {
    return null;
  }
  return objectPath;
}

/**
 * 販売ページの閲覧を1回数える（出品者にだけ見せる閲覧回数、2026-10-29追加）。
 * 回数は`packStats/{packId}`に持つ（`stickerPacks`は公開読み取りのため、
 * そこには置かない）。誰が見たかは保存せず、回数だけを足す。出品者本人の閲覧は
 * 数えない。未ログインの閲覧も数える（認証不要）。同じ訪問での重複は、
 * クライアント側（sessionStorage）で防ぐ。
 */
export const recordStickerPackView = onCall(
  { region: "asia-northeast1" },
  async (request) => {
    const packId = request.data?.packId;
    if (typeof packId !== "string" || !packId) {
      throw new HttpsError("invalid-argument", "packIdが必要です");
    }
    const packDoc = await db.collection("stickerPacks").doc(packId).get();
    if (!packDoc.exists) {
      throw new HttpsError("not-found", "ぺったんが見つかりません");
    }
    if (request.auth?.uid && packDoc.data()?.creatorId === request.auth.uid) {
      return { counted: false };
    }
    await db
      .collection("packStats")
      .doc(packId)
      .set(
        { viewCount: FieldValue.increment(1), updatedAt: FieldValue.serverTimestamp() },
        { merge: true },
      );
    return { counted: true };
  },
);

/**
 * ぺったん本体・閲覧回数・ストレージ上の画像を削除する（画像はベストエフォート）。
 * 出品者の直接削除（deleteStickerPack）と、運営の承認後の自動削除
 * （processScheduledPackDeletions）で共有する。
 */
async function deletePackAndAssets(
  packId: string,
  data: FirebaseFirestore.DocumentData,
): Promise<void> {
  const creatorId = typeof data.creatorId === "string" ? data.creatorId : "";
  await db.collection("stickerPacks").doc(packId).delete();
  // 出品者向けの閲覧回数も、孤児にならないよう一緒に消す
  await db.collection("packStats").doc(packId).delete();

  const stickers = (data.stickers as { imageUrl: string }[] | undefined) ?? [];
  const bucket = getStorage().bucket();
  await Promise.all(
    stickers.map(async (s) => {
      const path = storagePathFromDownloadUrl(s.imageUrl, creatorId);
      if (!path) return;
      try {
        await bucket.file(path).delete({ ignoreNotFound: true });
      } catch (err) {
        logger.warn(`ストレージオブジェクトの削除に失敗しました: ${path}`, err);
      }
    }),
  );
}

/**
 * 出品者が自分のぺったんを削除する。誰か1人でも現在所有していれば
 * （ownerCount > 0）直接は削除できず、運営への削除の申請
 * （requestStickerPackDeletion）が要る（購入済みユーザーの手持ちスタンプを
 * 勝手に消さないため）。ストレージ上の画像も併せてベストエフォートで削除する。
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
      throw new HttpsError("not-found", "ぺったんが見つかりません");
    }
    const data = doc.data()!;
    if (data.creatorId !== uid) {
      throw new HttpsError("permission-denied", "自分が出品したぺったんのみ削除できます");
    }
    const ownerCount = typeof data.ownerCount === "number" ? data.ownerCount : 0;
    if (ownerCount > 0) {
      throw new HttpsError(
        "failed-precondition",
        "このぺったんは現在利用しているユーザーがいるため、直接は削除できません。削除を運営へ申請してください",
      );
    }
    await deletePackAndAssets(packId, data);
  },
);

// ---------------------------------------------------------------------
// 出品済みぺったんの削除の申請→運営の承認→日時を指定して自動削除（2026-11-17追加）。
// 利用者がいる（ownerCount > 0）ぺったんは、出品者が直接削除できず、削除を申請する。
// 運営（管理者）は、承認のときに削除する日時を指定する。承認すると、そのぺったんを
// 入手した人だけにお知らせ（users/{uid}/notices）を送り、指定の時刻に
// processScheduledPackDeletionsが完全に削除する。申請は
// `packDeletionRequests/{packId}`（書き込みはCloud Functionsのみ）。
// ---------------------------------------------------------------------

function assertAdmin(request: CallableRequest): void {
  if (request.auth?.token.admin !== true) {
    throw new HttpsError("permission-denied", "管理者のみ実行できます");
  }
}

function readPackId(data: unknown): string {
  const packId = (data as { packId?: unknown } | undefined)?.packId;
  if (typeof packId !== "string" || !packId) {
    throw new HttpsError("invalid-argument", "packIdが必要です");
  }
  return packId;
}

/** 申請の対象。stickerIdがあれば、ぺったんの中の1枚の削除。 */
function readDeletionTarget(data: unknown): {
  packId: string;
  stickerId: string | undefined;
  requestId: string;
} {
  const packId = readPackId(data);
  const raw = (data as { stickerId?: unknown } | undefined)?.stickerId;
  if (raw !== undefined && (typeof raw !== "string" || !raw)) {
    throw new HttpsError("invalid-argument", "stickerIdが正しくありません");
  }
  const stickerId = typeof raw === "string" ? raw : undefined;
  return { packId, stickerId, requestId: deletionRequestId(packId, stickerId) };
}

function readDeletionStatus(value: unknown): PackDeletionStatus {
  return typeof value === "string" ? (value as PackDeletionStatus) : "pending";
}

/** そのぺったんを入手した人（`ownedStickerPacks`の持ち主）のuid一覧。 */
async function ownerUidsOfPack(packId: string): Promise<string[]> {
  const snap = await db
    .collectionGroup("ownedStickerPacks")
    .where("packId", "==", packId)
    .get();
  const uids: string[] = [];
  for (const doc of snap.docs) {
    const uid = doc.ref.parent.parent?.id;
    if (uid) uids.push(uid);
  }
  return uids;
}

/** 入手した全員の`ownedStickerPacks`のうち、そのぺったんの分を削除する（500件ずつ）。 */
async function removeOwnedRecords(packId: string): Promise<number> {
  let removed = 0;
  for (;;) {
    const snap = await db
      .collectionGroup("ownedStickerPacks")
      .where("packId", "==", packId)
      .limit(500)
      .get();
    if (snap.empty) return removed;
    const batch = db.batch();
    for (const doc of snap.docs) batch.delete(doc.ref);
    await batch.commit();
    removed += snap.size;
  }
}

/**
 * そのぺったんを入手した人だけに、お知らせ（`users/{uid}/notices`、アプリの
 * 設定>運営>お便りに並ぶ）を保存し、プッシュ通知を送る。送った人数を返す。
 */
async function notifyPackOwners(
  packId: string,
  message: string,
  deleteAt: Date,
): Promise<number> {
  const uids = await ownerUidsOfPack(packId);
  if (uids.length === 0) return 0;

  // 個別のお知らせの保存（500件ずつ）
  for (let i = 0; i < uids.length; i += 500) {
    const batch = db.batch();
    for (const uid of uids.slice(i, i + 500)) {
      batch.set(db.collection("users").doc(uid).collection("notices").doc(), {
        content: message,
        kind: "packDeletion",
        packId,
        deleteAt: Timestamp.fromDate(deleteAt),
        createdAt: FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  // プッシュ通知（お便りと同じ送り方。稼働中のアカウントのみ）
  const official = (await db.doc("system/official").get()).data();
  const title: string =
    typeof official?.name === "string" && official.name
      ? official.name
      : OFFICIAL_DEFAULT_NAME;
  const iconUrl: string | null =
    typeof official?.iconUrl === "string" ? official.iconUrl : null;
  const androidTokens: string[] = [];
  const webTokens: string[] = [];
  for (let i = 0; i < uids.length; i += 300) {
    const refs = uids.slice(i, i + 300).map((uid) => db.collection("users").doc(uid));
    const docs = await db.getAll(...refs);
    for (const userDoc of docs) {
      if (!userDoc.exists || userDoc.data()?.accountStatus !== "active") continue;
      const tokens = await loadFcmTokens(userDoc.id, userDoc.data()?.fcmTokens);
      for (const entry of tokens) {
        if (entry.platform === "android") androidTokens.push(entry.token);
        else if (entry.platform === "web") webTokens.push(entry.token);
      }
    }
  }
  const body = message.length > 100 ? `${message.slice(0, 100)}…` : message;
  const sentAtMs = Date.now();
  const messaging = getMessaging();
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
        sentAt: String(sentAtMs),
      },
      android: { priority: "high" },
    });
  }
  for (let i = 0; i < webTokens.length; i += 500) {
    await messaging.sendEachForMulticast({
      tokens: webTokens.slice(i, i + 500),
      webpush: {
        notification: {
          title,
          body: withSentTime(body, sentAtMs),
          icon: iconUrl ?? undefined,
        },
        data: { isDm: "true", conversationId: "", roomId: "" },
        fcmOptions: { link: "/" },
      },
    });
  }
  return uids.length;
}

/** 出品者が、利用者のいるぺったんの削除を、運営へ申請する（理由は必須）。 */
export const requestStickerPackDeletion = onCall(
  { region: "asia-northeast1" },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }
    const { packId, stickerId, requestId } = readDeletionTarget(request.data);
    const reason = validateDeletionText(request.data?.reason, "削除の理由", { required: true });
    if (!reason.ok) throw new HttpsError("invalid-argument", reason.message);

    const packDoc = await db.collection("stickerPacks").doc(packId).get();
    if (!packDoc.exists) {
      throw new HttpsError("not-found", "ぺったんが見つかりません");
    }
    const pack = packDoc.data()!;
    if (pack.creatorId !== uid) {
      throw new HttpsError("permission-denied", "自分が出品したぺったんのみ申請できます");
    }
    const ownerCount = typeof pack.ownerCount === "number" ? pack.ownerCount : 0;
    if (ownerCount <= 0) {
      throw new HttpsError(
        "failed-precondition",
        "このぺったんは利用している人がいないので、申請せずに直接削除できます",
      );
    }
    if (pack.deleteScheduledAt) {
      throw new HttpsError("already-exists", "すでに削除が予定されています");
    }
    // 1枚の削除: 下限・代表・存在を確認する
    let stickerName = "";
    if (stickerId) {
      const list = (pack.stickers as StickerInput[] | undefined) ?? [];
      const check = validateStickerRemoval(
        list.map((s) => s.stickerId),
        stickerId,
        typeof pack.coverStickerId === "string" ? pack.coverStickerId : null,
        MIN_STICKERS_PER_PACK,
      );
      if (!check.ok) throw new HttpsError("failed-precondition", check.message);
      stickerName = list.find((s) => s.stickerId === stickerId)?.name ?? "";
    }
    const reqRef = db.collection("packDeletionRequests").doc(requestId);
    const existing = await reqRef.get();
    if (existing.exists) {
      const status = readDeletionStatus(existing.data()?.status);
      if (status === "pending" || status === "scheduled" || status === "failed") {
        throw new HttpsError("already-exists", "すでに削除を申請しています");
      }
    }
    // 却下・取り消し・完了のあとの再申請は、新しい申請として上書きする
    await reqRef.set({
      packId,
      kind: stickerId ? "sticker" : "pack",
      ...(stickerId ? { stickerId, stickerName } : {}),
      packName: typeof pack.name === "string" ? pack.name : "",
      creatorId: uid,
      reason: reason.value,
      ownerCount,
      status: "pending" satisfies PackDeletionStatus,
      requestedAt: FieldValue.serverTimestamp(),
    });
    return { requested: true };
  },
);

/**
 * 削除の申請を承認し、削除する日時を指定する（管理者のみ）。日時は今から24時間以上先。
 * ぺったんに`deleteScheduledAt`を付けて新しい入手を止め、入手した人だけにお知らせを送る。
 */
export const approveStickerPackDeletion = onCall(
  { region: "asia-northeast1", timeoutSeconds: 300 },
  async (request) => {
    assertAdmin(request);
    const { packId, stickerId, requestId } = readDeletionTarget(request.data);
    // 緊急（urgent）は、周知の最短の期間（24時間）を設けず、すぐに削除する（権利侵害など、
    // 待てない場合）。お知らせは、同じように送る。削除は、次の5分ごとの処理で実行される
    const urgent = request.data?.urgent === true;
    const deleteAt: Validated<Date> = urgent
      ? { ok: true, value: new Date() }
      : validateDeleteAt(request.data?.deleteAt, new Date());
    if (!deleteAt.ok) throw new HttpsError("invalid-argument", deleteAt.message);

    const reqRef = db.collection("packDeletionRequests").doc(requestId);
    const reqDoc = await reqRef.get();
    if (!reqDoc.exists) {
      throw new HttpsError("not-found", "削除の申請が見つかりません");
    }
    const status = readDeletionStatus(reqDoc.data()?.status);
    if (!canTransition(status, "scheduled")) {
      throw new HttpsError("failed-precondition", "この申請は、承認できる状態ではありません");
    }
    const packRef = db.collection("stickerPacks").doc(packId);
    const packDoc = await packRef.get();
    if (!packDoc.exists) {
      throw new HttpsError("not-found", "ぺったんが見つかりません");
    }
    const packName: string =
      typeof packDoc.data()?.name === "string" ? packDoc.data()!.name : "";

    let notice = packDeletionNoticeText(packName, deleteAt.value, urgent);
    if (stickerId) {
      // 1枚の削除: ぺったんの入手は止めない（deleteScheduledAtは付けない）
      const list = (packDoc.data()?.stickers as StickerInput[] | undefined) ?? [];
      const target = list.find((s) => s.stickerId === stickerId);
      if (!target) {
        throw new HttpsError("not-found", "その画像は、すでにぺったんにありません");
      }
      notice = stickerDeletionNoticeText(packName, target.name, deleteAt.value, urgent);
    } else {
      await packRef.update({ deleteScheduledAt: Timestamp.fromDate(deleteAt.value) });
    }
    await reqRef.update({
      status: "scheduled" satisfies PackDeletionStatus,
      scheduledDeleteAt: Timestamp.fromDate(deleteAt.value),
      urgent,
      decidedAt: FieldValue.serverTimestamp(),
      decidedBy: request.auth!.uid,
      error: FieldValue.delete(),
    });

    let notified = 0;
    try {
      notified = await notifyPackOwners(packId, notice, deleteAt.value);
      await reqRef.update({ noticeCount: notified, noticeError: FieldValue.delete() });
    } catch (error) {
      logger.error("ぺったんの削除のお知らせに失敗", { packId, error });
      await reqRef.update({ noticeError: String(error).slice(0, 300) });
    }
    await writeAdminAuditLog({
      adminUid: request.auth!.uid,
      action: "approvePackDeletion",
      targetUserIds: [typeof reqDoc.data()?.creatorId === "string" ? reqDoc.data()!.creatorId : ""].filter(Boolean),
      note: `packId=${packId}${stickerId ? ` stickerId=${stickerId}` : ""} 削除日時=${deleteAt.value.toISOString()}${urgent ? " 緊急" : ""} 通知=${notified}人`,
    });
    return { scheduled: true, notified };
  },
);

/** 削除の申請を却下する（管理者のみ）。理由は任意（出品者に表示される）。 */
export const rejectStickerPackDeletion = onCall(
  { region: "asia-northeast1" },
  async (request) => {
    assertAdmin(request);
    const { requestId } = readDeletionTarget(request.data);
    const note = validateDeletionText(request.data?.note, "却下の理由", { required: false });
    if (!note.ok) throw new HttpsError("invalid-argument", note.message);

    const reqRef = db.collection("packDeletionRequests").doc(requestId);
    const reqDoc = await reqRef.get();
    if (!reqDoc.exists) {
      throw new HttpsError("not-found", "削除の申請が見つかりません");
    }
    if (!canTransition(readDeletionStatus(reqDoc.data()?.status), "rejected")) {
      throw new HttpsError("failed-precondition", "この申請は、却下できる状態ではありません");
    }
    await reqRef.update({
      status: "rejected" satisfies PackDeletionStatus,
      decisionNote: note.value,
      decidedAt: FieldValue.serverTimestamp(),
      decidedBy: request.auth!.uid,
    });
    await writeAdminAuditLog({
      adminUid: request.auth!.uid,
      action: "rejectPackDeletion",
      targetUserIds: [typeof reqDoc.data()?.creatorId === "string" ? reqDoc.data()!.creatorId : ""].filter(Boolean),
      note: `packId=${reqDoc.data()?.packId ?? requestId}${reqDoc.data()?.stickerId ? ` stickerId=${reqDoc.data()!.stickerId}` : ""}`,
      reason: note.value || undefined,
    });
    return { rejected: true };
  },
);

/** 承認済みの削除の予定を取り消す（管理者のみ）。ぺったんはそのまま残り、入手も再開する。 */
export const cancelScheduledPackDeletion = onCall(
  { region: "asia-northeast1" },
  async (request) => {
    assertAdmin(request);
    const { packId, stickerId, requestId } = readDeletionTarget(request.data);
    const reqRef = db.collection("packDeletionRequests").doc(requestId);
    const reqDoc = await reqRef.get();
    if (!reqDoc.exists) {
      throw new HttpsError("not-found", "削除の申請が見つかりません");
    }
    if (!canTransition(readDeletionStatus(reqDoc.data()?.status), "cancelled")) {
      throw new HttpsError("failed-precondition", "この削除の予定は、取り消せる状態ではありません");
    }
    const packRef = db.collection("stickerPacks").doc(packId);
    if (!stickerId && (await packRef.get()).exists) {
      await packRef.update({ deleteScheduledAt: FieldValue.delete() });
    }
    await reqRef.update({
      status: "cancelled" satisfies PackDeletionStatus,
      decidedAt: FieldValue.serverTimestamp(),
      decidedBy: request.auth!.uid,
    });
    await writeAdminAuditLog({
      adminUid: request.auth!.uid,
      action: "cancelPackDeletion",
      targetUserIds: [typeof reqDoc.data()?.creatorId === "string" ? reqDoc.data()!.creatorId : ""].filter(Boolean),
      note: `packId=${packId}${stickerId ? ` stickerId=${stickerId}` : ""}`,
    });
    return { cancelled: true };
  },
);

/**
 * ぺったんの配列から、画像1枚を取り除く（画像ファイルは消さない）。すでに無ければ何もしない
 * （何度実行しても安全）。下限・代表の検証は、申請・承認の時に済んでいるため、ここでは見ない。
 */
async function removeStickerFromPack(packId: string, stickerId: string): Promise<void> {
  const ref = db.collection("stickerPacks").doc(packId);
  await db.runTransaction(async (tx) => {
    const doc = await tx.get(ref);
    if (!doc.exists) return;
    const list = (doc.data()?.stickers as StickerInput[] | undefined) ?? [];
    if (!list.some((s) => s.stickerId === stickerId)) return;
    tx.update(ref, {
      stickers: list.filter((s) => s.stickerId !== stickerId),
      updatedAt: FieldValue.serverTimestamp(),
    });
  });
}

/**
 * 出品者が、利用者のいないぺったんから、画像1枚を直接削除する。利用者がいるぺったんは、
 * 運営への申請（requestStickerPackDeletion、stickerId付き）が要る。
 */
export const deleteStickerFromPack = onCall(
  { region: "asia-northeast1" },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }
    const { packId, stickerId } = readDeletionTarget(request.data);
    if (!stickerId) {
      throw new HttpsError("invalid-argument", "stickerIdが必要です");
    }
    const ref = db.collection("stickerPacks").doc(packId);
    const doc = await ref.get();
    if (!doc.exists) {
      throw new HttpsError("not-found", "ぺったんが見つかりません");
    }
    const pack = doc.data()!;
    if (pack.creatorId !== uid) {
      throw new HttpsError("permission-denied", "自分が出品したぺったんのみ編集できます");
    }
    const ownerCount = typeof pack.ownerCount === "number" ? pack.ownerCount : 0;
    if (ownerCount > 0) {
      throw new HttpsError(
        "failed-precondition",
        "このぺったんは現在利用しているユーザーがいるため、直接は削除できません。削除を運営へ申請してください",
      );
    }
    const list = (pack.stickers as StickerInput[] | undefined) ?? [];
    const check = validateStickerRemoval(
      list.map((s) => s.stickerId),
      stickerId,
      typeof pack.coverStickerId === "string" ? pack.coverStickerId : null,
      MIN_STICKERS_PER_PACK,
    );
    if (!check.ok) throw new HttpsError("failed-precondition", check.message);
    await removeStickerFromPack(packId, stickerId);
  },
);

/**
 * 出品済みぺったんの1枚の画像を、差し替える（運営の許可は不要）。stickerId・並び順は
 * 変えないので、入手した人の手持ちの対応は壊れない。旧画像のファイルは、過去のメッセージ
 * （送信時の画像URLを保存している）のために消さない。nameとrolesは、渡されたときだけ変える。
 */
export const replaceStickerImage = onCall(
  { region: "asia-northeast1" },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }
    const { packId, stickerId } = readDeletionTarget(request.data);
    if (!stickerId) {
      throw new HttpsError("invalid-argument", "stickerIdが必要です");
    }
    const imageUrl = request.data?.imageUrl;
    if (typeof imageUrl !== "string" || !imageUrl) {
      throw new HttpsError("invalid-argument", "imageUrlが必要です");
    }
    // 他人の画像・外部のURLを指せないよう、出品者自身のstickerPackAssets配下のURLだけを受ける
    if (!storagePathFromDownloadUrl(imageUrl, uid)) {
      throw new HttpsError("invalid-argument", "imageUrlが正しくありません");
    }
    const name = request.data?.name;
    if (name !== undefined && (typeof name !== "string" || !name.trim())) {
      throw new HttpsError("invalid-argument", "nameが正しくありません");
    }
    const roles = request.data?.roles;
    if (roles !== undefined && !Array.isArray(roles)) {
      throw new HttpsError("invalid-argument", "rolesが正しくありません");
    }

    const ref = db.collection("stickerPacks").doc(packId);
    await db.runTransaction(async (tx) => {
      const doc = await tx.get(ref);
      if (!doc.exists) {
        throw new HttpsError("not-found", "ぺったんが見つかりません");
      }
      const pack = doc.data()!;
      if (pack.creatorId !== uid) {
        throw new HttpsError("permission-denied", "自分が出品したぺったんのみ編集できます");
      }
      if (pack.deleteScheduledAt) {
        throw new HttpsError("failed-precondition", "削除が予定されているぺったんは、編集できません");
      }
      const list = (pack.stickers as StickerInput[] | undefined) ?? [];
      if (!list.some((s) => s.stickerId === stickerId)) {
        throw new HttpsError("not-found", "その画像は、このぺったんにありません");
      }
      tx.update(ref, {
        stickers: list.map((s) =>
          s.stickerId !== stickerId
            ? s
            : {
                ...s,
                imageUrl,
                ...(typeof name === "string" ? { name: name.trim() } : {}),
                ...(Array.isArray(roles)
                  ? { roles: roles.filter((r): r is string => typeof r === "string") }
                  : {}),
              },
        ),
        updatedAt: FieldValue.serverTimestamp(),
      });
    });
  },
);

/**
 * 出品済みぺったんの画像の役割（メッセージ内容に応じた提案に使う）を、後から付け直す
 * （運営の許可は不要。画像・stickerIdは変わらず、提案の出方だけが変わる）。
 * 渡したぺったんの`roles`だけを置き換える。空の配列で、役割なしに戻せる。
 */
export const updateStickerRoles = onCall(
  { region: "asia-northeast1" },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }
    const packId = readPackId(request.data);
    const parsed = parseRoleUpdates(request.data?.roles);
    if (!parsed.ok) throw new HttpsError("invalid-argument", parsed.message);

    const ref = db.collection("stickerPacks").doc(packId);
    await db.runTransaction(async (tx) => {
      const doc = await tx.get(ref);
      if (!doc.exists) {
        throw new HttpsError("not-found", "ぺったんが見つかりません");
      }
      const pack = doc.data()!;
      if (pack.creatorId !== uid) {
        throw new HttpsError("permission-denied", "自分が出品したぺったんのみ編集できます");
      }
      if (pack.deleteScheduledAt) {
        throw new HttpsError("failed-precondition", "削除が予定されているぺったんは、編集できません");
      }
      const list = (pack.stickers as StickerInput[] | undefined) ?? [];
      const rolesById = new Map(parsed.value.map((u) => [u.stickerId, u.roles]));
      for (const id of rolesById.keys()) {
        if (!list.some((s) => s.stickerId === id)) {
          throw new HttpsError("not-found", `stickerId "${id}" は、このぺったんにありません`);
        }
      }
      tx.update(ref, {
        stickers: list.map((s) =>
          rolesById.has(s.stickerId) ? { ...s, roles: rolesById.get(s.stickerId)! } : s,
        ),
        updatedAt: FieldValue.serverTimestamp(),
      });
    });
  },
);

const PACK_DELETION_BATCH_LIMIT = 20;

/**
 * 指定の日時になった削除の予定を、実行する（5分ごと）。入手した人の`ownedStickerPacks`、
 * ぺったん本体、画像を削除する。何度実行しても安全（すでに消えていれば、完了にするだけ）。
 */
export const processScheduledPackDeletions = onSchedule(
  { schedule: "every 5 minutes", region: "asia-northeast1", timeoutSeconds: 540 },
  async () => {
    const due = await db
      .collection("packDeletionRequests")
      .where("status", "==", "scheduled")
      .where("scheduledDeleteAt", "<=", Timestamp.now())
      .limit(PACK_DELETION_BATCH_LIMIT)
      .get();
    for (const reqDoc of due.docs) {
      // 1枚の削除の申請は、文書IDがpackId__stickerIdのため、packIdは本文から読む
      const packId = typeof reqDoc.data().packId === "string" ? reqDoc.data().packId : reqDoc.id;
      const stickerId =
        reqDoc.data().kind === "sticker" && typeof reqDoc.data().stickerId === "string"
          ? (reqDoc.data().stickerId as string)
          : undefined;
      try {
        if (stickerId) {
          // 1枚だけ、ぺったんの配列から取り除く。画像ファイルは、過去のメッセージ
          // （送信時の画像URLを保存している）のために消さない
          await removeStickerFromPack(packId, stickerId);
        } else {
          // 持ち主の記録を先に消す（途中で失敗しても、次の回で、残りを消せる）
          await removeOwnedRecords(packId);
          const packDoc = await db.collection("stickerPacks").doc(packId).get();
          if (packDoc.exists) await deletePackAndAssets(packId, packDoc.data()!);
        }
        await reqDoc.ref.update({
          status: "completed" satisfies PackDeletionStatus,
          completedAt: FieldValue.serverTimestamp(),
        });
        logger.info(`予定の時刻になった削除を実行しました: ${packId}${stickerId ? `/${stickerId}` : ""}`);
      } catch (error) {
        logger.error("ぺったんの予定の削除に失敗", { packId, error });
        await reqDoc.ref.update({
          status: "failed" satisfies PackDeletionStatus,
          error: String(error).slice(0, 300),
        });
      }
    }
  },
);

// ---------------------------------------------------------------------
// daidai横丁: 購入付与フロー（2026-08-11追加）。無料ぺったんの直接付与・
// 有料ぺったんのStripe Checkout経由の付与、どちらも最終的にこの
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
 * ユーザーが所有しているぺったんをアンインストール（所有解除）する。
 * grantOwnershipの対称形として、ownedStickerPacksドキュメントを削除し
 * ownerCountを1減らす（2026-08-11追加、functions/src/index.tsのcreateStickerPack
 * コメントで予告していたアンインストール連動の実処理）。salesCountは
 * 「これまでの累計販売数」という別の指標のため変更しない。これによって
 * ownerCountが0に戻れば、出品者はdeleteStickerPackでぺったんを削除できるように
 * なる。無料・有料どちらのぺったんでも、PAID_PACKS_ENABLEDに関係なく常に許可する。
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
        throw new HttpsError("failed-precondition", "このぺったんは所有していません");
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
 * ぺったんの入手を開始する。無料ぺったん（price===0）はStripeを介さず直接
 * 付与し、有料ぺったんはStripe Checkout Session（都度払い）を作成してその
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
      throw new HttpsError("not-found", "ぺったんが見つかりません");
    }
    const pack = packDoc.data()!;

    const ownedRef = db
      .collection("users")
      .doc(uid)
      .collection("ownedStickerPacks")
      .doc(packId);
    if ((await ownedRef.get()).exists) {
      throw new HttpsError("already-exists", "このぺったんはすでに入手済みです");
    }

    // 削除が予定されているぺったんは、新しく入手できない（運営が日時を決めた時点で止める）
    if (pack.deleteScheduledAt) {
      throw new HttpsError(
        "failed-precondition",
        "このぺったんは、まもなく公開を終了するため、入手できません",
      );
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
              name: typeof pack.name === "string" ? pack.name : "ぺったん",
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
 * Stripeからの決済完了通知を受け取り、ぺったんを購入者に付与する。
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

    if (
      event.type === "checkout.session.completed" &&
      (event.data.object as Stripe.Checkout.Session).mode === "subscription"
    ) {
      // 極みの購入（決済リンク。client_reference_idに購入者のuidが入る、2026-10-17）
      const session = event.data.object as Stripe.Checkout.Session;
      // `{uid}__{経路}`（経路が無い従来の購入は`{uid}`だけ）。経路は記録用で、払う金額は
      // 決済リンク自体が決める（2026-10-20）。
      const { uid, channel } = parseKiwamiReference(session.client_reference_id);
      const customerId =
        typeof session.customer === "string" ? session.customer : session.customer?.id;
      const subscriptionId =
        typeof session.subscription === "string"
          ? session.subscription
          : session.subscription?.id;
      const userRef = uid ? db.collection("users").doc(uid) : null;
      // 決済リンクの`client_reference_id`は誰でも書き換えられる為、他人のuidを指して自分の
      // 支払いを結び付けられる（2026-11-21、Strixの指摘）。支払い済みでない決済は扱わず、
      // 別の顧客で有効な契約が既にある住人の紐付けは上書きしない（運営が確認する）。
      const existingRef = uid ? db.collection("kiwamiSubscriptions").doc(uid) : null;
      const existing = existingRef ? await existingRef.get() : null;
      const existingData = existing?.exists ? existing.data() : null;
      let conflictsWithActive = false;
      if (
        existingData &&
        existingData.customerId &&
        existingData.customerId !== customerId &&
        typeof existingData.subscriptionId === "string"
      ) {
        try {
          const current = await getStripeClient().subscriptions.retrieve(
            existingData.subscriptionId,
          );
          conflictsWithActive = ["active", "trialing", "past_due"].includes(current.status);
        } catch (err) {
          // 確認できない時は安全側（上書きしない）に倒す
          logger.error("Webhook: 既存の契約の状態を確認できません", err);
          conflictsWithActive = true;
        }
      }
      if (session.payment_status === "unpaid") {
        logger.error("Webhook: 未払いの極みの決済は扱いません", { uid, sessionId: session.id });
      } else if (conflictsWithActive) {
        logger.error("Webhook: 別の顧客で有効な極みの契約がある住人への紐付けは上書きしません", {
          uid,
          sessionId: session.id,
        });
      } else if (!uid || !userRef || !customerId || !(await userRef.get()).exists) {
        logger.error("Webhook: 極みの購入に紐づく住人が見つかりません", {
          uid,
          sessionId: session.id,
        });
      } else {
        await db
          .collection("kiwamiSubscriptions")
          .doc(uid)
          .set({
            customerId,
            subscriptionId: subscriptionId ?? null,
            channel,
            amountTotal: session.amount_total ?? null,
            paymentLinkId:
              typeof session.payment_link === "string"
                ? session.payment_link
                : session.payment_link?.id ?? null,
            updatedAt: FieldValue.serverTimestamp(),
          });
        await userRef.update({ subscriptionPlan: "kiwami" });
        logger.info(`極みを付与（購入）: ${uid}`);
      }
    } else if (
      event.type === "customer.subscription.deleted" ||
      (event.type === "customer.subscription.updated" &&
        ["canceled", "unpaid", "incomplete_expired"].includes(
          (event.data.object as Stripe.Subscription).status,
        ))
    ) {
      // 契約の終了（解約の期間満了・支払い失敗の打ち切り）で極みを解除する
      const subscription = event.data.object as Stripe.Subscription;
      const customerId =
        typeof subscription.customer === "string"
          ? subscription.customer
          : subscription.customer.id;
      const found = await db
        .collection("kiwamiSubscriptions")
        .where("customerId", "==", customerId)
        .get();
      for (const doc of found.docs) {
        // 同じ顧客でも、記録した契約と別の契約の終了では解除しない（2026-11-21、Strixの指摘）
        const recorded = doc.data().subscriptionId;
        if (typeof recorded === "string" && recorded !== subscription.id) continue;
        await db.collection("users").doc(doc.id).update({ subscriptionPlan: "free" });
        logger.info(`極みを解除（契約終了）: ${doc.id}`);
      }
    } else if (event.type === "checkout.session.completed") {
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
 * 停止・解除に合わせて、Firebase Authのアカウントも無効化・有効化する（2026-11-21）。
 * `revokeRefreshTokens`だけでは、停止中でも再ログイン（Google・パスキー・QR）で全ての
 * 機能が使えてしまう為（Strixの指摘）。無効化すると、新しいログインとIDトークンの
 * 更新が拒否される（発行済みのIDトークンは最長1時間有効）。失敗は警告に留める。
 */
async function setAuthDisabled(userId: string, disabled: boolean): Promise<void> {
  await getAuth()
    .updateUser(userId, { disabled })
    .catch((error) => {
      logger.warn(`Authの${disabled ? "無効化" : "有効化"}に失敗: ${userId}`, error);
    });
}

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
    await setAuthDisabled(targetUserId, suspend);
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
 * [userId]が長を務める広場を、削除の前に片付ける（管理者による削除用、2026-11-14）。
 * 他のメンバーがいれば、加入が最も早いメンバーへ長を譲る（長の権限は`ownerId`だけで
 * 決まる）。他にメンバーがいない広場は、残っても誰も使えないため広場ごと削除する。
 * 本人の削除（クライアントが先に譲渡を求める）と違い、管理者の削除では本人が操作
 * できないため、サーバーが自動で行う。 */
async function handOverOrCloseOwnedGroups(userId: string): Promise<void> {
  const owned = await db
    .collection("groups")
    .where("ownerId", "==", userId)
    .get();
  for (const group of owned.docs) {
    const data = group.data();
    const others: string[] = (data.memberIds ?? []).filter(
      (id: string) => id !== userId,
    );
    if (others.length === 0) {
      await db.recursiveDelete(group.ref);
      await db.doc(`groupInvites/${group.id}`).delete().catch(() => {});
      logger.info(`長のみの広場を削除: ${group.id}`);
      continue;
    }
    const joinedAt: Record<string, FirebaseFirestore.Timestamp | undefined> =
      data.memberJoinedAt ?? {};
    // 加入時刻が記録されていないメンバー（古い広場）は、一覧の並びの先頭を優先する。
    const ranked = [...others].sort((a, b) => {
      const ta = joinedAt[a]?.toMillis?.() ?? 0;
      const tb = joinedAt[b]?.toMillis?.() ?? 0;
      return ta - tb;
    });
    await group.ref.update({ ownerId: ranked[0] });
    logger.info(`長を自動で譲渡: ${group.id} → ${ranked[0]}`);
  }
}

/**
 * 管理者が、指定した住人のアカウントを削除する（2026-11-14）。違反への対応は「停止」
 * （`suspendUserAccount`）で行い、削除はデータを消すための操作（本人がログインできず
 * 不要になったアカウント等）として使う。削除しても、同じGoogleアカウントでの再登録は
 * 制限しない。
 *
 * - `immediate`がtrueなら、すぐ完全に削除する（復元不可）。falseなら本人の通常削除と
 *   同じ30日の猶予（その間にログインすれば復元できる）に入る。
 * - 長を務める広場は、自動で他のメンバーへ譲る（[handOverOrCloseOwnedGroups]）。
 * - 自分自身・他の管理者・便りは対象外。操作は監査ログに残す。
 */
export const deleteUserAccountByAdmin = onCall(
  { region: "asia-northeast1" },
  async (request) => {
    if (request.auth?.token.admin !== true) {
      throw new HttpsError("permission-denied", "管理者のみ実行できます");
    }
    const targetUserId = request.data?.targetUserId;
    if (typeof targetUserId !== "string" || !targetUserId) {
      throw new HttpsError("invalid-argument", "targetUserIdが必要です");
    }
    const immediate = request.data?.immediate;
    if (typeof immediate !== "boolean") {
      throw new HttpsError("invalid-argument", "immediateが必要です");
    }
    const note =
      typeof request.data?.note === "string"
        ? request.data.note.slice(0, 200)
        : undefined;
    if (targetUserId === request.auth.uid) {
      throw new HttpsError("failed-precondition", "自分自身は削除できません");
    }
    const userRef = db.collection("users").doc(targetUserId);
    const userDoc = await userRef.get();
    if (!userDoc.exists) {
      throw new HttpsError("not-found", "ユーザーが見つかりません");
    }
    const targetAuth = await getAuth()
      .getUser(targetUserId)
      .catch(() => null);
    if (targetAuth?.customClaims?.admin === true) {
      throw new HttpsError(
        "failed-precondition",
        "管理者のアカウントは削除できません",
      );
    }
    const status = userDoc.data()!.accountStatus;
    if (!immediate && status === "pendingDeletion") {
      throw new HttpsError(
        "failed-precondition",
        "すでに削除申請中です（すぐ削除するなら「すぐに完全削除」を選んでください）",
      );
    }

    await handOverOrCloseOwnedGroups(targetUserId);

    if (immediate) {
      await deleteAccount(targetUserId, userDoc.data()!);
    } else {
      await userRef.update({
        accountStatus: "pendingDeletion",
        deletionRequestedAt: FieldValue.serverTimestamp(),
      });
      await getAuth()
        .revokeRefreshTokens(targetUserId)
        .catch((error) => {
          logger.warn(`revokeRefreshTokensに失敗: ${targetUserId}`, error);
        });
    }
    await writeAdminAuditLog({
      adminUid: request.auth.uid,
      action: immediate ? "deleteAccount" : "scheduleDeleteAccount",
      targetUserIds: [targetUserId],
      ...(note ? { note } : {}),
    });
    logger.info(
      `管理者によるアカウント削除（${immediate ? "即時" : "30日の猶予"}）: ${targetUserId}`,
    );
  },
);

/**
 * 住人に極み（有料プラン）を付与/解除する（管理者のみ、2026-10-17追加）。
 * 購入の導線（Stripe Checkout・Webhook）ができるまでの手動の付与用。契約状態
 * `subscriptionPlan`はクライアントから書けず（firestore.rules）、ここ（Admin SDK）
 * だけが書く。操作は監査ログ`adminAuditLogs`に残す。
 */
export const setKiwamiPlan = onCall(
  { region: "asia-northeast1" },
  async (request) => {
    if (request.auth?.token.admin !== true) {
      throw new HttpsError("permission-denied", "管理者のみ実行できます");
    }
    const targetUserId = request.data?.targetUserId;
    if (typeof targetUserId !== "string" || !targetUserId) {
      throw new HttpsError("invalid-argument", "targetUserIdが必要です");
    }
    const kiwami = request.data?.kiwami;
    if (typeof kiwami !== "boolean") {
      throw new HttpsError("invalid-argument", "kiwamiが必要です");
    }
    const ref = db.collection("users").doc(targetUserId);
    const snapshot = await ref.get();
    if (!snapshot.exists) {
      throw new HttpsError("not-found", "住人が見つかりません");
    }
    await ref.update({ subscriptionPlan: kiwami ? "kiwami" : "free" });
    await writeAdminAuditLog({
      adminUid: request.auth.uid,
      action: kiwami ? "grantKiwami" : "revokeKiwami",
      targetUserIds: [targetUserId],
    });
    logger.info(`極みを${kiwami ? "付与" : "解除"}: ${targetUserId}`);
  },
);

/**
 * 住人の極みの契約状態をStripeから取得して返す（管理者のみ、2026-10-18追加）。
 * ポータルでキャンセルしても期間満了までは`subscriptionPlan`が`kiwami`のままなので、
 * 運営が「継続中」と「解約予定」を見分けるために使う。取得のみで何も変更しない。
 * state: none（Stripeの契約なし＝手動付与・無料）/ active（継続中）/
 * cancelScheduled（期間満了で終了予定）/ pastDue（支払い遅延）/ ended（終了済み）。
 */
export const getKiwamiSubscriptionStatus = onCall(
  { region: "asia-northeast1", secrets: [stripeSecretKey] },
  async (request) => {
    if (request.auth?.token.admin !== true) {
      throw new HttpsError("permission-denied", "管理者のみ実行できます");
    }
    const targetUserId = request.data?.targetUserId;
    if (typeof targetUserId !== "string" || !targetUserId) {
      throw new HttpsError("invalid-argument", "targetUserIdが必要です");
    }
    const doc = await db.collection("kiwamiSubscriptions").doc(targetUserId).get();
    const subscriptionId = doc.data()?.subscriptionId;
    const channel = typeof doc.data()?.channel === "string" ? doc.data()?.channel : null;
    if (typeof subscriptionId !== "string") {
      return { state: "none", periodEnd: null, channel, monthlyAmount: null };
    }
    const subscription = await getStripeClient().subscriptions.retrieve(subscriptionId);
    const itemPeriodEnd = subscription.items.data[0]?.current_period_end ?? null;
    const cancelScheduled =
      subscription.cancel_at_period_end || subscription.cancel_at !== null;
    let state: string;
    if (subscription.status === "canceled" || subscription.status === "incomplete_expired") {
      state = "ended";
    } else if (subscription.status === "past_due" || subscription.status === "unpaid") {
      state = "pastDue";
    } else if (cancelScheduled) {
      state = "cancelScheduled";
    } else {
      state = "active";
    }
    const endSeconds = subscription.cancel_at ?? itemPeriodEnd;
    return {
      state,
      periodEnd: endSeconds === null ? null : new Date(endSeconds * 1000).toISOString(),
      channel,
      monthlyAmount: subscription.items.data[0]?.price.unit_amount ?? null,
    };
  },
);

/**
 * 極みの契約管理（解約・カード変更）用のStripeカスタマーポータルのURLを返す
 * （2026-10-17追加）。購入済み（`kiwamiSubscriptions/{uid}`がある）住人のみ。
 */
export const createKiwamiPortalSession = onCall(
  { region: "asia-northeast1", secrets: [stripeSecretKey] },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }
    const doc = await db.collection("kiwamiSubscriptions").doc(uid).get();
    const customerId = doc.data()?.customerId;
    if (typeof customerId !== "string") {
      throw new HttpsError("not-found", "契約が見つかりません");
    }
    const session = await getStripeClient().billingPortal.sessions.create({
      customer: customerId,
      return_url: "https://daidai.rhing.jp",
    });
    return { url: session.url };
  },
);

/**
 * 通話の中継（TURN）の認証情報を返す（2026-10-21追加）。Cloudflare Realtime TURNの
 * APIで、短時間だけ有効な認証情報を発行する。キー・トークンはこの関数の中だけに置き、
 * クライアントには発行済みの`iceServers`だけを返す。ログイン済みの人だけ呼べる。
 * 有効期間は通話の長さに足りる程度（4時間）。クライアントは通話の開始時に1回呼ぶ。
 */
export const getTurnCredentials = onCall(
  { region: "asia-northeast1", secrets: [turnKeyId, turnKeyApiToken] },
  async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }
    const response = await fetch(
      `https://rtc.live.cloudflare.com/v1/turn/keys/${turnKeyId.value()}/credentials/generate-ice-servers`,
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${turnKeyApiToken.value()}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ ttl: 4 * 60 * 60 }),
      },
    );
    if (!response.ok) {
      logger.error("TURN認証情報の発行に失敗しました", response.status);
      throw new HttpsError("internal", "中継サーバーの認証情報を取得できません");
    }
    const body = (await response.json()) as { iceServers?: unknown };
    return { iceServers: filterTurnIceServers(body.iceServers) };
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
  action:
    | "suspend"
    | "unsuspend"
    | "viewProfile"
    | "grantKiwami"
    | "revokeKiwami"
    | "deleteAccount"
    | "scheduleDeleteAccount"
    | "approvePackDeletion"
    | "rejectPackDeletion"
    | "cancelPackDeletion"
    | "resolveReport"
    | "approveThemePack"
    | "rejectThemePack"
    | "suspendThemePack"
    | "blockThemePackSubmission"
    | "unblockThemePackSubmission";
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
    await Promise.all(changed.map((id) => setAuthDisabled(id, suspend)));
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
 * 複数の住人にまとめて極みを付与/剥奪する（管理者のみ）。1回100件まで。
 * 自分自身・重複・不在・削除申請中は対象外で、理由つきで返す（自分への操作は
 * 住人詳細から`setKiwamiPlan`で行う）。操作は監査ログに1件でまとめて残す。
 */
export const setKiwamiPlans = onCall(
  { region: "asia-northeast1" },
  async (request) => {
    if (request.auth?.token.admin !== true) {
      throw new HttpsError("permission-denied", "管理者のみ実行できます");
    }
    const kiwami = request.data?.kiwami;
    if (typeof kiwami !== "boolean") {
      throw new HttpsError("invalid-argument", "kiwamiが必要です");
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
      const reason = classifyTarget(snapshot.data(), false, false);
      if (reason) {
        skipped.push({ id, reason });
        continue;
      }
      await writer.update(snapshot.ref, {
        subscriptionPlan: kiwami ? "kiwami" : "free",
      });
      changed.push(id);
    }
    await writer.commit();
    if (changed.length > 0) {
      await writeAdminAuditLog({
        adminUid: request.auth.uid,
        action: kiwami ? "grantKiwami" : "revokeKiwami",
        targetUserIds: changed,
      });
    }
    logger.info(
      `極み一括${kiwami ? "付与" : "剥奪"}: ${changed.length}件（対象外${skipped.length}件）`,
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
      const tokens = await loadFcmTokens(userDoc.id, userDoc.data().fcmTokens);
      for (const entry of tokens) {
        if (entry.platform === "android") androidTokens.push(entry.token);
        else if (entry.platform === "web") webTokens.push(entry.token);
      }
    }

    const body = message.length > 100 ? `${message.slice(0, 100)}…` : message;
    const sentAtMs = Date.now();
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
          sentAt: String(sentAtMs),
        },
        android: { priority: "high" },
      });
    }
    for (let i = 0; i < webTokens.length; i += 500) {
      await messaging.sendEachForMulticast({
        tokens: webTokens.slice(i, i + 500),
        webpush: {
          notification: {
            title,
            body: withSentTime(body, sentAtMs),
            icon: iconUrl ?? undefined,
          },
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


/**
 * 住人[userId]のFCMトークン一覧を返す（2026-11-07）。保存先は`users/{uid}/private/fcm`
 * （本人のみ読める）。`users`本体は全ログイン者が読めるため、他人の端末トークンを
 * 読まれないよう移した。移行期間のため、旧保存先（`users/{uid}.fcmTokens`、[legacy]）も
 * 併せて読んでトークンの重複を除く。移行スクリプト（`functions/scripts/
 * migrate-fcm-tokens.cjs`）を実行して旧フィールドが無くなれば[legacy]は常に空になる。
 */
async function loadFcmTokens(
  userId: string,
  legacy?: unknown
): Promise<FcmTokenEntry[]> {
  const snap = await db.doc(`users/${userId}/private/fcm`).get();
  return mergeFcmTokenEntries(legacy, snap.data()?.tokens);
}

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
  const base = buildBaseMessagePreview(message);
  // 添付と一緒に送った文字（`caption`、2026-11-01）があれば、通知本文の先頭に付ける。
  const caption =
    typeof message.caption === "string" ? message.caption.trim() : "";
  if (caption === "" || base.body === "") return base;
  return { ...base, body: `${caption.slice(0, 60)} ${base.body}` };
}

function buildBaseMessagePreview(
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
    case "multi": {
      // 複数添付（2026-10-16）。画像・動画・ファイルの件数を並べ、
      // プレビュー画像は先頭の動画サムネイルまたは画像。
      const items = (message.attachments ?? []) as Array<{
        mimeType?: string;
        url?: string;
        thumbnailUrl?: string;
      }>;
      const images = items.filter((a) => a.mimeType?.startsWith("image/"));
      const videos = items.filter((a) => a.mimeType?.startsWith("video/"));
      const files = items.length - images.length - videos.length;
      const parts: string[] = [];
      if (images.length > 0) parts.push(`画像${images.length}枚`);
      if (videos.length > 0) parts.push(`動画${videos.length}本`);
      if (files > 0) parts.push(`ファイル${files}件`);
      const first = items.find((a) => a.mimeType?.startsWith("image/") || a.thumbnailUrl);
      return {
        body: `[${parts.join("・") || "添付"}]`,
        previewUrl: first?.mimeType?.startsWith("image/")
          ? (first.url ?? null)
          : (first?.thumbnailUrl ?? null),
      };
    }
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

/** 受信者がいま、この寄合のメッセージ画面を開いている（アプリが前面）か（2026-11-13）。
 * クライアントが`conversationPrefs`の`viewing`（`roomId`・`at`）を約30秒ごとに更新し、
 * 閉じる・離れる時に消す。クラッシュ等で消えなくても、更新が90秒止まれば開いていない扱い。 */
const VIEWING_FRESH_MS = 90_000;
async function isViewingRoom(
  recipientId: string,
  conversationId: string,
  roomId: string,
): Promise<boolean> {
  const prefsDoc = await db
    .doc(`users/${recipientId}/conversationPrefs/${conversationId}`)
    .get();
  const viewing = prefsDoc.data()?.viewing;
  if (!viewing || viewing.roomId !== roomId) return false;
  const at =
    typeof viewing.at?.toMillis === "function" ? viewing.at.toMillis() : 0;
  return Date.now() - at < VIEWING_FRESH_MS;
}

/** [recipientId]が[senderId]を一対でブロックしているか（2026-10-11）。 */
async function isBlockedBy(
  recipientId: string,
  senderId: string,
): Promise<boolean> {
  const doc = await db.doc(`users/${recipientId}/blockedUsers/${senderId}`).get();
  return doc.exists;
}

async function sendMessageNotification(params: {
  isDm: boolean;
  conversationId: string;
  roomId: string;
  messageId: string;
  message: FirebaseFirestore.DocumentData;
}): Promise<void> {
  const { isDm, conversationId, roomId, messageId, message } = params;
  if (message.silent === true) return;
  if (
    message.contentType === "call" ||
    message.contentType === "accountDeleted" ||
    message.contentType === "botAdded" ||
    message.contentType === "botRemoved"
  ) {
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
  // `@`メンション（2026-10-11追加）。有効なメンションがあれば、通知先を
  // メンションされた人だけに絞り、ミュート設定も無視する。
  let mentionRecipients: string[] | null = null;
  let senderNamePrefix = "";
  if (isDm) {
    const dmDoc = await db.doc(`directMessages/${conversationId}`).get();
    const participants: string[] = dmDoc.data()?.participants ?? [];
    // 送信者をブロックしている相手には通知しない（2026-10-11）。
    recipientIds = await excludeBlockers(
      participants.filter((id) => id !== senderId),
      senderId,
      isBlockedBy,
    );
    if (botName === null) {
      mentionRecipients = resolveMentionRecipients(message, {
        senderId,
        isDm: true,
        memberIds: participants,
      });
    } else if (typeof message.assistantOwnerId === "string") {
      // AI連携の投稿（2026-11-09）。送信者は`bot:`のため、候補から持ち主本人が
      // 除かれるよう、送信者に持ち主のidを渡す。
      mentionRecipients = resolveMentionRecipients(message, {
        senderId: message.assistantOwnerId,
        isDm: true,
        memberIds: participants,
      });
    }
    if (botName !== null) {
      // BOT由来（bot API、2026-11-09）は送信者の`users`が無い為、BOT名を題にする。
      title = botName;
      iconUrl = null;
    } else {
      const identity = resolveSenderIdentity(sender, conversationId);
      title = identity.name;
      iconUrl = identity.iconUrl;
    }
  } else {
    const groupDoc = await db.doc(`groups/${conversationId}`).get();
    const memberIds: string[] = groupDoc.data()?.memberIds ?? [];
    recipientIds = memberIds.filter((id) => id !== senderId);
    if (botName === null) {
      const groupData = groupDoc.data() ?? {};
      mentionRecipients = resolveMentionRecipients(message, {
        senderId,
        isDm: false,
        memberIds,
        ownerId: groupData.ownerId as string | undefined,
        roleAssignments: groupData.roleAssignments,
        memberPermissions: groupData.memberPermissions,
      });
    } else if (typeof message.assistantOwnerId === "string") {
      // AI連携の投稿は個人宛のメンションだけ（`@everyone`・ロール宛はAPIが受け付けない）。
      mentionRecipients = resolveMentionRecipients(message, {
        senderId: message.assistantOwnerId,
        isDm: false,
        memberIds,
      });
    }
    const inviteDoc = await db.doc(`groupInvites/${conversationId}`).get();
    title =
      (inviteDoc.data()?.name as string) ??
      (groupDoc.data()?.name as string) ??
      "";
    // アイコンは送信者の会話用カードのもの（一対と同じ解決、2026-10-11変更）。
    // 送信者が未設定、またはWebhook（BOT）由来なら広場のカードのアイコン。
    // 誰が送ったか分かるよう、本文の先頭に送信者名を付ける。
    const groupIcon = (inviteDoc.data()?.iconUrl as string) ?? null;
    if (botName === null) {
      const identity = resolveSenderIdentity(sender, conversationId);
      iconUrl = identity.iconUrl ?? groupIcon;
      senderNamePrefix = identity.name;
    } else {
      iconUrl = groupIcon;
    }
  }
  // AIエージェント連携（bot API）の投稿は、所有者本人には通知しない（2026-11-09）。
  if (typeof message.assistantOwnerId === "string") {
    recipientIds = recipientIds.filter((id) => id !== message.assistantOwnerId);
  }
  const isMention = mentionRecipients !== null;
  if (mentionRecipients !== null) recipientIds = mentionRecipients;
  if (recipientIds.length === 0) return;

  const preview = buildMessagePreview(message);
  // AI連携（bot API）の投稿は「持ち主のその語らいでの呼び名 [AI]」にする
  // （AIの名前は出さない。呼び名が無ければ`@Rhing Seed`、2026-11-09）。
  let botLabel = botName;
  if (botName !== null && typeof message.assistantOwnerId === "string") {
    const owner = (await db.doc(`users/${message.assistantOwnerId}`).get()).data();
    if (owner) {
      const identity = resolveSenderIdentity(owner, conversationId).name;
      botLabel = `${identity === owner.rhingSeed ? `@${identity}` : identity} [AI]`;
    }
  }
  // 一対では、AI連携の投稿の通知の題も持ち主の呼び名にする（BOT名ではなく）。
  const dmAssistantTitle = isDm && botName !== null && botLabel !== botName;
  if (dmAssistantTitle) title = botLabel!;
  const body =
    dmAssistantTitle
      ? preview.body
      : botName !== null
      ? `${botLabel}: ${preview.body}`
      : withSenderName(preview.body, senderNamePrefix);
  // 送信時刻（epoch ms）。Androidは端末側で表示時点の日時と比べて整形する
  // （日付・年の出し分け）。Webは自動表示のためここで日本時間の時刻を付ける。
  const sentAtMs: number =
    typeof message.sentAt?.toMillis === "function"
      ? message.sentAt.toMillis()
      : Date.now();
  const previewUrl = preview.previewUrl;

  const targets: RecipientTokens[] = [];
  for (const recipientId of recipientIds) {
    // メンションされた人は、会話をミュートしていても通知する。
    if (
      !isMention &&
      (await isConversationMuted(recipientId, conversationId, roomId))
    ) {
      continue;
    }
    // その寄合を開いている人には通知しない（メンションも含む、2026-11-14に、
    // 以前のメンション除外をやめた）。
    if (await isViewingRoom(recipientId, conversationId, roomId)) {
      continue;
    }
    const recipientDoc = await db.doc(`users/${recipientId}`).get();
    const tokens = await loadFcmTokens(recipientId, recipientDoc.data()?.fcmTokens);
    const target = tokensOfRecipient(recipientId, tokens);
    if (target.android.length > 0 || target.web.length > 0) targets.push(target);
  }
  if (targets.length === 0) return;

  await sendToEachRecipient(
    targets,
    // Androidの通知アイコン/画像はローカルアセットかバイト列でしか渡せないため、
    // data-onlyで送りクライアント（lib/push_notifications.dart）側で
    // flutter_local_notificationsを使い自前でリッチ通知を組み立てる。
    (recipientId) => ({
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
        isMention: String(isMention),
        sentAt: String(sentAtMs),
        // 送信取消の時に、この通知を特定して閉じるため（2026-11-15）。
        messageId,
        // 使っていないアカウント宛ての通知をタップした時に、宛先へ切り替えるため（2026-11-24）。
        recipientId,
      },
      android: { priority: "high" },
    }),
    (recipientId) => ({
      webpush: {
        notification: {
          title,
          body: withSentTime(body, sentAtMs),
          icon: iconUrl ?? undefined,
          image: previewUrl ?? undefined,
          // 送信取消の時に、この通知を特定して閉じるため（2026-11-15）。
          tag: messageId,
        },
        // 通知タップで該当の語らいまで開くためのディープリンク情報
        // （2026-09-02追加、web/firebase-messaging-sw.js参照）。FCMが
        // webpush通知を自動表示する際、この`data`が表示されたNotificationの
        // `.data`としてnotificationclickハンドラから参照できる。
        data: {
          isDm: String(isDm),
          conversationId,
          roomId,
          isMention: String(isMention),
          messageId,
          recipientId,
        },
        fcmOptions: { link: "/" },
      },
    }),
  );
}

/**
 * 承認不要（`requiresApproval == false`）の広場へ、承認を待たずに参加する
 * （2026-10-11追加）。非メンバーが自分を`memberIds`に足す書き込みは
 * firestore.rulesで許さないため、追加はAdmin SDKのここでだけ行う。
 * 承認フロー（`respondToJoinRequest`）と同じ内容を反映する: メンバー・全寄合の
 * `memberIds`、`memberRoles`、加入時刻（加入前の履歴を見せない設定の根拠）、
 * 実効権限キャッシュ（基準ロールの権限）。保留中の参加リクエストがあれば
 * 承認済みにして整合させる。
 */
export const joinGroup = onCall(
  { region: "asia-northeast1" },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "ログインが必要です");
    const groupId = request.data?.groupId;
    if (typeof groupId !== "string" || groupId.length === 0) {
      throw new HttpsError("invalid-argument", "groupIdが必要です");
    }
    const userDoc = await db.doc(`users/${uid}`).get();
    if (!userDoc.exists || userDoc.data()?.accountStatus !== "active") {
      throw new HttpsError("permission-denied", "参加できません");
    }

    const groupRef = db.doc(`groups/${groupId}`);
    const groupDoc = await groupRef.get();
    if (!groupDoc.exists) throw new HttpsError("not-found", "広場が見つかりません");
    const decision = decideJoin(groupDoc.data()!, uid);
    if (decision === "denied") {
      throw new HttpsError(
        "failed-precondition",
        "この広場は参加に承認が必要です",
      );
    }
    if (decision === "already-member") return { joined: false };

    const [roomsSnapshot, rolesSnapshot] = await Promise.all([
      groupRef.collection("rooms").get(),
      groupRef.collection("roles").get(),
    ]);
    const permissions = newMemberPermissions(
      rolesSnapshot.docs.map((d) => d.data()),
    );

    const batch = db.batch();
    batch.update(groupRef, {
      memberIds: FieldValue.arrayUnion(uid),
      [`memberRoles.${uid}`]: "member",
      [`memberJoinedAt.${uid}`]: FieldValue.serverTimestamp(),
      [`memberPermissions.${uid}`]: permissions,
    });
    for (const room of roomsSnapshot.docs) {
      batch.update(room.ref, { memberIds: FieldValue.arrayUnion(uid) });
    }
    const requestRef = groupRef.collection("joinRequests").doc(uid);
    const requestDoc = await requestRef.get();
    if (requestDoc.exists && requestDoc.data()?.status === "pending") {
      batch.update(requestRef, {
        status: "accepted",
        respondedAt: FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
    return { joined: true };
  },
);

/**
 * 指定ユーザーのAndroid/Webの全端末へ、同じ内容のプッシュ通知を1件送る
 * （2026-10-11追加）。`sendMessageNotification`と同じ形式（Androidはdata-only、
 * Webはwebpush）。ミュート等の判定は呼び出し側で済ませておく。
 */
async function sendPushToUsers(params: {
  recipientIds: string[];
  title: string;
  body: string;
  iconUrl: string | null;
  isDm: boolean;
  conversationId: string;
  roomId: string;
}): Promise<void> {
  const { recipientIds, title, body, iconUrl, isDm, conversationId, roomId } =
    params;
  const targets: RecipientTokens[] = [];
  for (const recipientId of recipientIds) {
    const recipientDoc = await db.doc(`users/${recipientId}`).get();
    const tokens = await loadFcmTokens(recipientId, recipientDoc.data()?.fcmTokens);
    const target = tokensOfRecipient(recipientId, tokens);
    if (target.android.length > 0 || target.web.length > 0) targets.push(target);
  }
  if (targets.length === 0) return;
  const sentAtMs = Date.now();
  await sendToEachRecipient(
    targets,
    (recipientId) => ({
      data: {
        title,
        body,
        iconUrl: iconUrl ?? "",
        previewUrl: "",
        isDm: String(isDm),
        conversationId,
        roomId,
        isMention: "false",
        sentAt: String(sentAtMs),
        recipientId,
      },
      android: { priority: "high" },
    }),
    (recipientId) => ({
      webpush: {
        notification: {
          title,
          body: withSentTime(body, sentAtMs),
          icon: iconUrl ?? undefined,
        },
        data: {
          isDm: String(isDm),
          conversationId,
          roomId,
          isMention: "false",
          recipientId,
        },
        fcmOptions: { link: "/" },
      },
    }),
  );
}

/**
 * 絶縁の提案（`severanceRequestedBy`が相手のuserIdに変わった時）を、相手へ
 * プッシュ通知で1件知らせる（2026-10-11追加）。大事な同意依頼のため、相手が
 * 一対をミュートしていても送る。提案者をブロックしている相手には送らない。
 * 提案→取り消しの連打で通知を連発させないよう、直近1時間以内に通知済みなら
 * 送らない（`severanceNotifiedAt`はこの関数だけが書くサーバー専用の項目）。
 */
export const onSeveranceProposed = onDocumentUpdated(
  { document: "directMessages/{dmId}", region: "asia-northeast1" },
  async (event) => {
    const before = event.data?.before?.data();
    const after = event.data?.after?.data();
    if (!after) return;
    const notifiedAt = after.severanceNotifiedAt as
      | FirebaseFirestore.Timestamp
      | undefined;
    const target = severanceNotifyTarget(
      before,
      after,
      notifiedAt?.toMillis?.() ?? null,
      Date.now(),
    );
    if (!target) return;

    const { dmId } = event.params;
    const recipients = await excludeBlockers(
      [target.recipientId],
      target.proposerId,
      isBlockedBy,
    );
    if (recipients.length === 0) return;

    const proposerDoc = await db.doc(`users/${target.proposerId}`).get();
    if (!proposerDoc.exists) return;
    const identity = resolveSenderIdentity(proposerDoc.data()!, dmId);

    await event.data!.after.ref.update({
      severanceNotifiedAt: FieldValue.serverTimestamp(),
    });
    await sendPushToUsers({
      recipientIds: recipients,
      title: identity.name,
      body: "絶縁を提案しました。承認または辞退してください",
      iconUrl: identity.iconUrl,
      isDm: true,
      conversationId: dmId,
      roomId: "",
    });
  },
);

/**
 * 広場への参加リクエスト（新規・却下後の再申請）を、承認できる人（長と
 * `manageJoinRequests`権限者）にだけプッシュで知らせる（2026-10-11追加）。
 * メッセージは作らないため、寄合の全メンバーには見えない。承認作業の
 * 通知なので、広場をミュートしていても送る（メンション通知と同じ扱い）。
 */
export const onJoinRequestWritten = onDocumentWritten(
  {
    document: "groups/{groupId}/joinRequests/{requesterId}",
    region: "asia-northeast1",
  },
  async (event) => {
    const before = event.data?.before?.data();
    const after = event.data?.after?.data();
    if (!isNewPendingRequest(before, after)) return;

    const { groupId, requesterId } = event.params;
    const groupDoc = await db.doc(`groups/${groupId}`).get();
    if (!groupDoc.exists) return;
    const group = groupDoc.data()!;
    const recipientIds = resolveJoinRequestRecipients(group, requesterId);
    if (recipientIds.length === 0) return;

    const inviteDoc = await db.doc(`groupInvites/${groupId}`).get();
    const title =
      (inviteDoc.data()?.name as string) ?? (group.name as string) ?? "";
    const iconUrl = (inviteDoc.data()?.iconUrl as string) ?? null;
    // 旧名`requesterRhingId`のままの文書も読む（2026-09-23の改名前に作成）。
    const seed =
      (after?.requesterRhingSeed as string | undefined) ??
      (after?.requesterRhingId as string | undefined) ??
      "";
    const body = seed
      ? `@${seed} が参加をリクエストしました`
      : "参加リクエストが届きました";

    const androidTokens: string[] = [];
    const webTokens: string[] = [];
    for (const recipientId of recipientIds) {
      const recipientDoc = await db.doc(`users/${recipientId}`).get();
      const tokens = await loadFcmTokens(recipientId, recipientDoc.data()?.fcmTokens);
      for (const entry of tokens) {
        if (entry.platform === "android") androidTokens.push(entry.token);
        else if (entry.platform === "web") webTokens.push(entry.token);
      }
    }
    if (androidTokens.length === 0 && webTokens.length === 0) return;

    const sentAtMs = Date.now();
    const messaging = getMessaging();
    if (androidTokens.length > 0) {
      await messaging.sendEachForMulticast({
        tokens: androidTokens,
        data: {
          title,
          body,
          iconUrl: iconUrl ?? "",
          previewUrl: "",
          isDm: "false",
          conversationId: groupId,
          roomId: "",
          isMention: "false",
          sentAt: String(sentAtMs),
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
            body: withSentTime(body, sentAtMs),
            icon: iconUrl ?? undefined,
          },
          data: {
            isDm: "false",
            conversationId: groupId,
            roomId: "",
            isMention: "false",
          },
          fcmOptions: { link: "/" },
        },
      });
    }
  },
);

/**
 * 友達申請（新規・却下後の再申請）を、申請を受ける側へプッシュで知らせる
 * （2026-10-13追加、Android・Web）。通知の見た目は一対のメッセージ通知と同じ
 * （title=送信者が相手に見せる呼び名、アイコン=その会話用カードのアイコン。
 * 友達申請の会話ID＝`friendRequests`の文書ID＝`pairId`）。タップはアプリを開くだけ
 * （`conversationId`を空にする）。送信者をブロックしている相手には送らない。
 */
export const onFriendRequestWritten = onDocumentWritten(
  { document: "friendRequests/{requestId}", region: "asia-northeast1" },
  async (event) => {
    const before = event.data?.before?.data();
    const after = event.data?.after?.data();
    const target = resolveFriendRequestRecipient(before, after);
    if (!target) return;

    const recipients = await excludeBlockers(
      [target.recipientId],
      target.senderId,
      isBlockedBy,
    );
    if (recipients.length === 0) return;

    const senderDoc = await db.doc(`users/${target.senderId}`).get();
    if (!senderDoc.exists) return;
    const identity = resolveSenderIdentity(
      senderDoc.data()!,
      event.params.requestId,
    );
    await sendPushToUsers({
      recipientIds: recipients,
      title: identity.name,
      body: friendRequestBody(after?.message),
      iconUrl: identity.iconUrl,
      isDm: true,
      conversationId: "",
      roomId: "",
    });
  },
);

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
  // bot追加・削除のお知らせ（システムメッセージ）は未読にしない（2026-11-09）。
  if (message.contentType === "botAdded" || message.contentType === "botRemoved") {
    return;
  }
  const senderId: string = message.senderId;

  let recipientIds: string[];
  if (isDm) {
    const dmDoc = await db.doc(`directMessages/${conversationId}`).get();
    const participants: string[] = dmDoc.data()?.participants ?? [];
    // ブロック中の送信者の分は未読にしない（2026-10-11）。
    recipientIds = await excludeBlockers(
      participants.filter((id) => id !== senderId),
      senderId,
      isBlockedBy,
    );
  } else {
    const groupDoc = await db.doc(`groups/${conversationId}`).get();
    const memberIds: string[] = groupDoc.data()?.memberIds ?? [];
    recipientIds = memberIds.filter((id) => id !== senderId);
  }
  // AIエージェント連携（bot API）の投稿は、所有者本人の未読にしない（2026-11-09）。
  if (typeof message.assistantOwnerId === "string") {
    recipientIds = recipientIds.filter((id) => id !== message.assistantOwnerId);
  }
  // 通話の記録は、その通話に出ていた人の未読にしない（2026-11-26）。
  if (message.contentType === "call" && Array.isArray(message.callJoinedUserIds)) {
    const joined = new Set<string>(message.callJoinedUserIds);
    recipientIds = recipientIds.filter((id) => !joined.has(id));
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
        messageId: event.params.messageId,
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
// 送信予定（2026-11-10追加）
//
// クライアントが`scheduledMessages/{id}`に、送るメッセージ（`message`）と送信時刻（`sendAt`）を
// 保存する。毎分、時刻を過ぎた予定を`messages`へ書き出す。通知・未読の加算は、書き出した
// メッセージに対する既存の`onDmMessageCreated`/`onGroupMessageCreated`が行う。
// ---------------------------------------------------------------------------

/** 予定1件を送る。送れなければ`failed`にして理由を残す。 */
async function dispatchScheduledMessage(
  ref: FirebaseFirestore.DocumentReference,
): Promise<void> {
  // 二重送信を避ける為、`pending`のものだけを`sending`に確保する。
  const claimed = await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const data = snap.data();
    if (!data || data.status !== "pending") return null;
    tx.update(ref, { status: "sending" });
    return data;
  });
  if (!claimed) return;

  const scope = claimed.scope;
  const conversationId = String(claimed.conversationId ?? "");
  const roomId = String(claimed.roomId ?? "");
  const messageId = String(claimed.messageId ?? "");
  const senderId = claimed.createdBy;
  const message = claimed.message as Record<string, unknown> | undefined;

  const fail = (reason: string) =>
    ref.update({
      status: "failed",
      failReason: reason,
      failedAt: FieldValue.serverTimestamp(),
    });

  if (!message || !conversationId || !roomId || !messageId) {
    await fail("invalid");
    return;
  }

  const convRef = db
    .collection(scope === "dm" ? "directMessages" : "groups")
    .doc(conversationId);
  const roomRef = convRef
    .collection("rooms")
    .doc(roomId);
  const [convSnap, roomSnap] = await Promise.all([convRef.get(), roomRef.get()]);
  const failure = scheduledSendFailure({
    scope,
    senderId,
    dmParticipants: convSnap.data()?.participants ?? null,
    groupMemberIds: convSnap.data()?.memberIds ?? null,
    roomMemberIds:
      scope === "dm"
        ? roomSnap.data()?.participants ?? null
        : roomSnap.data()?.memberIds ?? null,
    conversationExists: convSnap.exists,
    roomExists: roomSnap.exists,
  });
  if (failure) {
    await fail(failure);
    return;
  }

  const batch = db.batch();
  // 同じメッセージIDで`create`する為、再実行しても二重には送られない。
  // 予約の中身はクライアントが自由に書けるマップなので、Admin SDKで写す時に、人間のメッセージ
  // では作れない項目（BOT・Webhookの表示名とアイコン）を除き、AIエージェントの投稿を示す
  // `assistantOwnerId`は予約した本人のものだけ残す（他人・BOTの名義の偽装を防ぐ、
  // 2026-11-16、Strixの指摘）。
  const safeMessage: Record<string, unknown> = { ...message };
  delete safeMessage.botName;
  delete safeMessage.botIconUrl;
  if (safeMessage.assistantOwnerId !== senderId) delete safeMessage.assistantOwnerId;
  batch.create(roomRef.collection("messages").doc(messageId), {
    ...safeMessage,
    // 送信者は、予約した本人に固定する（保存された中身の`senderId`は信用しない）。
    senderId,
    sentAt: FieldValue.serverTimestamp(),
  });
  batch.update(roomRef, { lastMessageAt: FieldValue.serverTimestamp() });
  batch.update(convRef, {
    lastMessageAt: FieldValue.serverTimestamp(),
    lastMessageSenderId: senderId,
    lastMessageContentType: claimed.lastMessageContentType ?? "text",
    lastMessagePreview: claimed.lastMessagePreview ?? null,
  });
  batch.delete(ref);
  try {
    await batch.commit();
  } catch (error) {
    logger.error("送信予定の送信に失敗", { id: ref.id, error });
    await fail("invalid");
  }
}

export const sendScheduledMessages = onSchedule(
  { schedule: "every 1 minutes", region: "asia-northeast1" },
  async () => {
    const due = await db
      .collection("scheduledMessages")
      .where("status", "==", "pending")
      .where("sendAt", "<=", Timestamp.now())
      .limit(SCHEDULED_BATCH_LIMIT)
      .get();
    for (const doc of due.docs) {
      try {
        await dispatchScheduledMessage(doc.ref);
      } catch (error) {
        logger.error("送信予定の処理に失敗", { id: doc.id, error });
      }
    }
    // 失敗したまま長く残った予定を掃除する。
    const nowMs = Date.now();
    const failed = await db
      .collection("scheduledMessages")
      .where("status", "==", "failed")
      .limit(SCHEDULED_BATCH_LIMIT)
      .get();
    for (const doc of failed.docs) {
      const at = (doc.data().failedAt as Timestamp | undefined)?.toMillis();
      if (at !== undefined && isFailedScheduledExpired(at, nowMs)) {
        await doc.ref.delete();
      }
    }
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
        messageId: event.params.messageId,
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

/**
 * メッセージが削除された（送信取消など）時に、出ている通知を閉じる合図を、送信者以外の
 * 参加者の端末（Android・Web）へ送る（2026-11-15）。データだけのFCMで、端末側
 * （`lib/push_notifications.dart`・`web/firebase-messaging-sw.js`）が`messageId`で通知を
 * 特定して閉じる。ミュート・ブロックは見ない（閉じるだけの合図のため）。
 */
async function sendMessageRecall(params: {
  participantIds: unknown;
  senderId: unknown;
  conversationId: string;
  roomId: string;
  messageId: string;
}): Promise<void> {
  const recipients = recallRecipients(params.participantIds, params.senderId);
  if (recipients.length === 0) return;
  const tokens: string[] = [];
  for (const userId of recipients) {
    const userDoc = await db.doc(`users/${userId}`).get();
    const entries = await loadFcmTokens(userId, userDoc.data()?.fcmTokens);
    for (const entry of entries) {
      if (entry.platform === "android" || entry.platform === "web") {
        tokens.push(entry.token);
      }
    }
  }
  if (tokens.length === 0) return;
  await getMessaging().sendEachForMulticast({
    tokens,
    data: recallPayload(params),
    android: { priority: "high" },
  });
}

/**
 * 語らい内の画像・動画の保存期間（2026-11-28、ユーザー決定）。無料は30日、極みは180日。
 * 判断は`retention.ts`（Firebase非依存）。ここはFirestore・Storageの窓口だけ。
 * アルバム（`albumFiles/`）は別のパスへコピー済みなので、対象にしない。
 */
const retentionDeleteEnabled = defineString("RETENTION_DELETE_ENABLED", { default: "false" });

const retentionStore: RetentionStore = {
  async deleteFile(path) {
    await getStorage().bucket().file(path).delete({ ignoreNotFound: true });
  },
  async markExpired(docPath) {
    // 印を付け、期限（`expiresAt`）を消す。索引から外れ、翌日以降に拾い直されない。
    await db.doc(docPath).update({
      attachmentsExpired: true,
      expiresAt: FieldValue.delete(),
    });
  },
};

/** 送信者が極みかを、サーバー側で読む（botやシステムの送信者は`users`に無く、無料の扱い）。 */
async function senderIsKiwami(senderId: unknown): Promise<boolean> {
  if (typeof senderId !== "string" || senderId.length === 0) return false;
  const snap = await db.doc(`users/${senderId}`).get();
  return isKiwamiPlan(snap.data());
}

/** 送信日時（ミリ秒）。無ければ今。 */
function messageSentAtMs(data: ChatMessageData): number {
  const sentAt = data.sentAt;
  return sentAt instanceof Timestamp ? sentAt.toMillis() : Date.now();
}

/**
 * 添付を持つメッセージが作られた時に、期限（`expiresAt`）を付ける。クライアントからは書かせない
 * （改造で好きな期限を付けられないように。`firestore.rules`のupdateは、この項目を許さない）。
 * サムネイル・再生用動画の生成も同じメッセージを更新するので、この項目だけを更新する。
 */
async function assignMessageExpiry(docPath: string, data: ChatMessageData | undefined): Promise<void> {
  if (!data || !hasExpirableAttachment(data)) return;
  const expiresAtMs = retentionExpiresAtMs(messageSentAtMs(data), await senderIsKiwami(data.senderId));
  await db.doc(docPath).update({ expiresAt: Timestamp.fromMillis(expiresAtMs) });
}

export const setDmMessageExpiry = onDocumentCreated(
  {
    document: "directMessages/{dmId}/rooms/{roomId}/messages/{messageId}",
    region: "asia-northeast1",
  },
  async (event) => {
    await assignMessageExpiry(
      `directMessages/${event.params.dmId}/rooms/${event.params.roomId}/messages/${event.params.messageId}`,
      event.data?.data(),
    );
  },
);

export const setGroupMessageExpiry = onDocumentCreated(
  {
    document: "groups/{groupId}/rooms/{roomId}/messages/{messageId}",
    region: "asia-northeast1",
  },
  async (event) => {
    await assignMessageExpiry(
      `groups/${event.params.groupId}/rooms/${event.params.roomId}/messages/${event.params.messageId}`,
      event.data?.data(),
    );
  },
);

/** メッセージが消えた時（送信取消・全員が削除）に、添付のファイルも消す。 */
async function deleteChatMessageFiles(docPath: string, data: ChatMessageData): Promise<void> {
  const { failed } = await deleteMessageAttachments(retentionStore, docPath, data);
  if (failed.length > 0) logger.warn("消えたメッセージの添付を消せなかった", { docPath, failed });
}

/**
 * 期限を過ぎた添付を、毎日消す。`RETENTION_DELETE_ENABLED`が`true`の時だけ消し、それ以外は、
 * 件数と先頭の数件をログに出すだけ（最初に、件数を確かめてから有効にする為）。消した後も、
 * メッセージは残し、`attachmentsExpired: true`にする（画面は「期限切れ」の表示になる）。
 */
export const cleanupExpiredChatAttachmentsDaily = onSchedule(
  { schedule: "45 4 * * *", timeZone: "Asia/Tokyo", region: "asia-northeast1", timeoutSeconds: 540 },
  async () => {
    const snap = await db
      .collectionGroup("messages")
      .where("expiresAt", "<=", Timestamp.now())
      .orderBy("expiresAt")
      .limit(RETENTION_EXPIRE_LIMIT)
      .get();
    const messages = snap.docs
      .filter((d) => conversationFromDocPath(d.ref.path) !== null)
      .map((d) => ({ docPath: d.ref.path, data: d.data() as ChatMessageData }));
    const result = await expireMessageAttachments(
      retentionStore,
      messages,
      retentionDeleteEnabled.value() === "true",
    );
    if (result.dryRun) {
      logger.info(`期限を過ぎた添付（消さずに数えただけ）: ${result.wouldExpire}件`, {
        examples: messages.slice(0, 5).map((m) => m.docPath),
      });
      return;
    }
    logger.info(`期限を過ぎた添付を消した: ${result.expired.length}件、失敗${result.failed.length}件`);
    if (result.failed.length > 0) logger.warn("消せなかったメッセージ", result.failed.slice(0, 20));
  },
);

/**
 * 一度きりの移行（管理者のみ）。この仕組みの前に送られた添付メッセージに、期限を付ける。
 * 期限は、送信日から30日（送信者が極みなら180日）と、予告の日から30日の、遅いほう。
 * `dryRun`なら数えるだけ。1回の呼び出しで`maxDocs`件まで処理し、続きは`nextCursor`で呼び直す。
 * 実行を終えたら、この関数はソースから削除する（過去の`...Once`と同じ運用）。
 */
export const backfillMessageExpiryOnce = onCall(
  { region: "asia-northeast1", timeoutSeconds: 540 },
  async (request) => {
    if (request.auth?.token.admin !== true) {
      throw new HttpsError("permission-denied", "管理者のみ実行できます");
    }
    const noticeAtMs = request.data?.noticeAtMs;
    if (typeof noticeAtMs !== "number" || !Number.isFinite(noticeAtMs)) {
      throw new HttpsError("invalid-argument", "noticeAtMs（予告の日時、ミリ秒）が必要です");
    }
    const dryRun = request.data?.dryRun !== false;
    const maxDocs = Math.min(Number(request.data?.maxDocs) || 2000, 5000);
    const types = ["image", "video", "file", "multi"];
    const kiwamiCache = new Map<string, boolean>();
    let scanned = 0;
    let updated = 0;
    let skipped = 0;
    let nextCursor: { type: string; path: string } | null = null;
    const startType = typeof request.data?.cursorType === "string" ? request.data.cursorType : types[0];
    const startPath = typeof request.data?.cursorPath === "string" ? request.data.cursorPath : null;
    for (const type of types.slice(types.indexOf(startType!))) {
      let q = db.collectionGroup("messages").where("contentType", "==", type).limit(300);
      if (type === startType && startPath) q = q.startAfter(db.doc(startPath));
      for (;;) {
        const page = await q.get();
        if (page.empty) break;
        const batch = db.batch();
        for (const d of page.docs) {
          scanned++;
          const data = d.data() as ChatMessageData;
          if (
            conversationFromDocPath(d.ref.path) === null ||
            data.expiresAt != null ||
            data.attachmentsExpired === true ||
            !hasExpirableAttachment(data)
          ) {
            skipped++;
            continue;
          }
          const senderId = typeof data.senderId === "string" ? data.senderId : "";
          if (!kiwamiCache.has(senderId)) kiwamiCache.set(senderId, await senderIsKiwami(senderId));
          const expiresAtMs = legacyExpiresAtMs(
            messageSentAtMs(data),
            kiwamiCache.get(senderId) === true,
            noticeAtMs,
          );
          updated++;
          if (!dryRun) batch.update(d.ref, { expiresAt: Timestamp.fromMillis(expiresAtMs) });
        }
        if (!dryRun) await batch.commit();
        const last = page.docs[page.docs.length - 1]!;
        if (scanned >= maxDocs) {
          nextCursor = { type, path: last.ref.path };
          break;
        }
        q = db.collectionGroup("messages").where("contentType", "==", type).limit(300).startAfter(last);
      }
      if (nextCursor) break;
    }
    logger.info(`期限の移行: 走査${scanned}、${dryRun ? "付与の予定" : "付与"}${updated}、対象外${skipped}`);
    return { scanned, updated, skipped, dryRun, nextCursor };
  },
);

export const onDmMessageDeleted = onDocumentDeleted(
  {
    document: "directMessages/{dmId}/rooms/{roomId}/messages/{messageId}",
    region: "asia-northeast1",
  },
  async (event) => {
    const message = event.data?.data();
    if (!message) return;
    await deleteChatMessageFiles(
      `directMessages/${event.params.dmId}/rooms/${event.params.roomId}/messages/${event.params.messageId}`,
      message,
    );
    const dmDoc = await db.doc(`directMessages/${event.params.dmId}`).get();
    await sendMessageRecall({
      participantIds: dmDoc.data()?.participants,
      senderId: message.senderId,
      conversationId: event.params.dmId,
      roomId: event.params.roomId,
      messageId: event.params.messageId,
    });
  },
);

export const onGroupMessageDeleted = onDocumentDeleted(
  {
    document: "groups/{groupId}/rooms/{roomId}/messages/{messageId}",
    region: "asia-northeast1",
  },
  async (event) => {
    const message = event.data?.data();
    if (!message) return;
    await deleteChatMessageFiles(
      `groups/${event.params.groupId}/rooms/${event.params.roomId}/messages/${event.params.messageId}`,
      message,
    );
    const groupDoc = await db.doc(`groups/${event.params.groupId}`).get();
    await sendMessageRecall({
      participantIds: groupDoc.data()?.memberIds,
      senderId: message.senderId,
      conversationId: event.params.groupId,
      roomId: event.params.roomId,
      messageId: event.params.messageId,
    });
  },
);

/**
 * 広場通話が始まった時に、広場のメンバー（開始者以外）へプッシュ通知を送る
 * （2026-10-21追加）。着信音は鳴らさず、通知だけを送る。ミュート中の広場には
 * 送らない。通知のタップで、その広場の語らいを開く（`conversationId`、
 * `lib/push_notifications.dart`）。iOSのプッシュは未実装のためAndroid・Webのみ。
 * アプリを開いている間は、アプリ内のバナー（`GroupIncomingCallListener`）もある。
 */
export const onGroupCallCreated = onDocumentCreated(
  { document: "groupCalls/{groupCallId}", region: "asia-northeast1" },
  async (event) => {
    const call = event.data?.data();
    if (!call || call.status !== "active") return;
    const groupId = call.groupId as string | undefined;
    const initiatorId = call.initiatorId as string | undefined;
    if (!groupId || !initiatorId) return;

    const recipientIds = groupCallRecipients(call.memberIds, initiatorId);
    if (recipientIds.length === 0) return;

    const [groupDoc, inviteDoc, initiatorDoc] = await Promise.all([
      db.doc(`groups/${groupId}`).get(),
      db.doc(`groupInvites/${groupId}`).get(),
      db.doc(`users/${initiatorId}`).get(),
    ]);
    const title =
      (inviteDoc.data()?.name as string) ??
      (groupDoc.data()?.name as string) ??
      "";
    const groupIcon = (inviteDoc.data()?.iconUrl as string) ?? null;
    const identity = initiatorDoc.exists
      ? resolveSenderIdentity(initiatorDoc.data()!, groupId)
      : { name: "", iconUrl: null };
    const iconUrl = identity.iconUrl ?? groupIcon;
    const body = groupCallNotificationBody(
      identity.name,
      call.isVideo === true,
    );
    const sentAtMs = Date.now();

    const targets: RecipientTokens[] = [];
    for (const recipientId of recipientIds) {
      if (await isConversationMuted(recipientId, groupId, "")) continue;
      const recipientDoc = await db.doc(`users/${recipientId}`).get();
      const tokens = await loadFcmTokens(recipientId, recipientDoc.data()?.fcmTokens);
      const target = tokensOfRecipient(recipientId, tokens);
      if (target.android.length > 0 || target.web.length > 0) targets.push(target);
    }
    if (targets.length === 0) return;

    await sendToEachRecipient(
      targets,
      (recipientId) => ({
        data: {
          title,
          body,
          iconUrl: iconUrl ?? "",
          previewUrl: "",
          isDm: "false",
          conversationId: groupId,
          roomId: "",
          isMention: "false",
          sentAt: String(sentAtMs),
          // Androidは着信通知（CallStyle、応答・拒否ボタン付き）として表示する（2026-11-12）。
          type: "incoming_group_call",
          callId: event.params.groupCallId,
          groupId,
          callerName: identity.name,
          isVideo: call.isVideo === true ? "true" : "false",
          // 緊急の発信（通話ボタンの長押し）。受け手の端末のおやすみモードを貫通して鳴らす
          // （受け手が端末の許可を与えている時だけ、2026-11-25）。
          urgent: call.urgent === true ? "true" : "false",
          // 使っていないアカウント宛ての着信を、宛先へ切り替えて応答するため（2026-11-24）。
          recipientId,
        },
        android: { priority: "high" },
      }),
      (recipientId) => ({
        webpush: {
          notification: {
            title,
            body: withSentTime(body, sentAtMs),
            icon: iconUrl ?? undefined,
          },
          data: {
            isDm: "false",
            conversationId: groupId,
            roomId: "",
            isMention: "false",
            recipientId,
          },
          fcmOptions: { link: "/" },
        },
      }),
    );
  },
);

/** 受信者ごとにまとめたFCMトークン。通知に宛先を載せるため、受信者ごとに送る（2026-11-24）。 */
type RecipientTokens = { recipientId: string; android: string[]; web: string[] };

/**
 * 通知の宛先を載せるため、受信者ごとにAndroid・Webへ送る（2026-11-24）。同じ端末で複数の
 * アカウントを使っていると、1つの端末のトークンが複数の受信者に登録されている。以前は全員の
 * トークンを1回にまとめて送っていたため、どのアカウント宛てか通知に書けなかった。
 * [buildAndroid]・[buildWeb]は、受信者のidから、トークン以外のメッセージ本体を作る。
 */
async function sendToEachRecipient(
  targets: RecipientTokens[],
  buildAndroid: (recipientId: string) => Omit<MulticastMessage, "tokens">,
  buildWeb: (recipientId: string) => Omit<MulticastMessage, "tokens">,
): Promise<void> {
  const messaging = getMessaging();
  await Promise.all(
    targets.map(async (target) => {
      if (target.android.length > 0) {
        await messaging.sendEachForMulticast({
          tokens: target.android,
          ...buildAndroid(target.recipientId),
        });
      }
      if (target.web.length > 0) {
        await messaging.sendEachForMulticast({
          tokens: target.web,
          ...buildWeb(target.recipientId),
        });
      }
    }),
  );
}

/** 受信者1人のトークンを、プラットフォームごとに仕分ける。 */
function tokensOfRecipient(
  recipientId: string,
  tokens: { token: string; platform: string }[],
): RecipientTokens {
  return {
    recipientId,
    android: tokens.filter((t) => t.platform === "android").map((t) => t.token),
    web: tokens.filter((t) => t.platform === "web").map((t) => t.token),
  };
}

/** 通話の着信通知を、鳴っている端末から消す（2026-11-12）。通話が終わった・応答された・
 * 拒否された時に、Androidの着信通知（CallStyle）を取り消す。 */
async function sendCallCancel(userIds: string[], callId: string): Promise<void> {
  const androidTokens: string[] = [];
  for (const userId of userIds) {
    const userDoc = await db.doc(`users/${userId}`).get();
    const tokens = await loadFcmTokens(userId, userDoc.data()?.fcmTokens);
    for (const entry of tokens) {
      if (entry.platform === "android") androidTokens.push(entry.token);
    }
  }
  if (androidTokens.length === 0) return;
  await getMessaging().sendEachForMulticast({
    tokens: androidTokens,
    data: { type: "call_cancel", callId },
    android: { priority: "high" },
  });
}

/**
 * 一対の通話の着信を、アプリを閉じている相手にも知らせる（2026-11-12）。Androidは着信通知
 * （CallStyle、右が緑の応答・左が赤の拒否）、アプリを開いている間はアプリ内のバナーが知らせる。
 * ブロック中の相手・ミュート中の一対には送らない。iOS・Webは対象外。
 */
export const onCallCreated = onDocumentCreated(
  { document: "calls/{callId}", region: "asia-northeast1" },
  async (event) => {
    const call = event.data?.data();
    if (!call || call.status !== "ringing") return;
    const callerId = call.callerId as string | undefined;
    const calleeId = call.calleeId as string | undefined;
    const dmId = call.dmId as string | undefined;
    if (!callerId || !calleeId || !dmId) return;
    if (await isBlockedBy(calleeId, callerId)) return;
    if (await isConversationMuted(calleeId, dmId, "")) return;

    const [callerDoc, calleeDoc] = await Promise.all([
      db.doc(`users/${callerId}`).get(),
      db.doc(`users/${calleeId}`).get(),
    ]);
    const identity = callerDoc.exists
      ? resolveSenderIdentity(callerDoc.data()!, dmId)
      : { name: "", iconUrl: null };
    const tokens = await loadFcmTokens(calleeId, calleeDoc.data()?.fcmTokens);
    const androidTokens = tokens
      .filter((entry) => entry.platform === "android")
      .map((entry) => entry.token);
    if (androidTokens.length === 0) return;
    await getMessaging().sendEachForMulticast({
      tokens: androidTokens,
      data: {
        type: "incoming_call",
        callId: event.params.callId,
        dmId,
        callerName: identity.name,
        iconUrl: identity.iconUrl ?? "",
        isVideo: call.isVideo === true ? "true" : "false",
        // 緊急の発信（通話ボタンの長押し）。受け手の端末のおやすみモードを貫通して鳴らす
        // （受け手が端末の許可を与えている時だけ、2026-11-25）。
        urgent: call.urgent === true ? "true" : "false",
        sentAt: String(Date.now()),
        // 使っていないアカウント宛ての着信を、宛先へ切り替えて応答するため（2026-11-24）。
        recipientId: calleeId,
      },
      android: { priority: "high", ttl: 60 * 1000 },
    });
  },
);

/** 一対の通話が呼び出し中でなくなったら（応答・拒否・終了・不在）、着信通知を消す。 */
export const onCallRingEnded = onDocumentUpdated(
  { document: "calls/{callId}", region: "asia-northeast1" },
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after) return;
    if (before.status !== "ringing" || after.status === "ringing") return;
    const calleeId = after.calleeId as string | undefined;
    if (!calleeId) return;
    await sendCallCancel([calleeId], event.params.callId);
  },
);

/** 広場の通話が終わったら、まだ鳴っている着信通知を消す。 */
export const onGroupCallRingEnded = onDocumentUpdated(
  { document: "groupCalls/{groupCallId}", region: "asia-northeast1" },
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after) return;
    if (before.status !== "active" || after.status === "active") return;
    const initiatorId = after.initiatorId as string | undefined;
    const memberIds = Array.isArray(after.memberIds)
      ? (after.memberIds as string[]).filter((id) => id !== initiatorId)
      : [];
    await sendCallCancel(memberIds, event.params.groupCallId);
  },
);

/** 通話の記録メッセージ（`contentType: 'call'`）の本文。UIは`callResult`で専用表示に切り替える。 */
const CALL_ENDED_CONTENT = "通話が終了しました";
const CALL_MISSED_CONTENT = "不在着信";
const CALL_CANCELLED_CONTENT = "キャンセル";

/** 呼び出し中のまま終了が書かれない一対の通話を不在着信にするまでの秒数（クライアントの30秒＋余裕）。 */
const DM_CALL_STALE_RINGING_MS = 90 * 1000;
/** 一対の通話のハートビート（15秒ごと）が途絶えたとみなす時間（クライアントの45秒に余裕を持たせる）。 */
const DM_CALL_HEARTBEAT_STALE_MS = 90 * 1000;
/** ハートビートを一度も書いていない`active`の通話を、残骸とみなす時間（`kCallNoHeartbeatMaxAge`と同じ）。 */
const DM_CALL_NO_HEARTBEAT_MAX_MS = 3 * 60 * 60 * 1000;
/** ハートビートが途絶えたとみなす秒数（`kGroupCallPresenceStaleAfter`と同じ）。 */
const GROUP_CALL_PRESENCE_STALE_MS = 45 * 1000;
/** 作成直後、まだ誰も参加していない間は放棄扱いにしない猶予（`kGroupCallAbandonedGrace`と同じ）。 */
const GROUP_CALL_ABANDONED_GRACE_MS = 60 * 1000;

/**
 * 通話の記録メッセージを、会話で最も古い寄合へ1件書く（2026-11-17）。
 * 以前は発信者の端末が送っており、アプリが落ちる・相手が先に切る等で欠落したため、
 * 通話ドキュメントの終了をトリガーにサーバーが書く。メッセージIDは通話ごとに決まるため、
 * トリガーが重複して発火しても1件にしかならない。通知は出さない（`sendMessageNotification`が
 * `call`を除外している）。
 */
async function writeCallRecordMessage(params: {
  isDm: boolean;
  conversationId: string;
  callId: string;
  senderId: string;
  result: CallRecordResult;
  startedAt: Timestamp | null;
  durationSeconds: number | null;
  isVideo: boolean;
  /** 通話を始めた寄合。空・削除済みなら最も古い寄合（2026-11-26）。 */
  roomId?: string | null;
  /** 通話に出ていた住人。これらの人は、記録を未読にしない（2026-11-26）。 */
  joinedUserIds?: string[] | null;
}): Promise<void> {
  const { isDm, conversationId, callId, senderId, result } = params;
  const missed = result !== "completed";
  const parentRef = db.doc(
    `${isDm ? "directMessages" : "groups"}/${conversationId}`,
  );
  // 通話を始めた寄合へ書く。指定が無い・寄合が削除済みなら、最も古い寄合へ。
  let roomRef: FirebaseFirestore.DocumentReference | null = null;
  if (params.roomId) {
    const started = parentRef.collection("rooms").doc(params.roomId);
    if ((await started.get()).exists) roomRef = started;
  }
  if (!roomRef) {
    const oldestRoom = await parentRef
      .collection("rooms")
      .orderBy("createdAt")
      .limit(1)
      .get();
    if (oldestRoom.empty) return;
    roomRef = oldestRoom.docs[0].ref;
  }
  const messageRef = roomRef.collection("messages").doc(`call_${callId}`);
  if ((await messageRef.get()).exists) return;
  const senderDoc = await db.doc(`users/${senderId}`).get();
  const content =
    result === "cancelled"
      ? CALL_CANCELLED_CONTENT
      : missed
        ? CALL_MISSED_CONTENT
        : CALL_ENDED_CONTENT;
  const batch = db.batch();
  batch.create(messageRef, {
    conversationId: roomRef.id,
    conversationType: isDm ? "dm" : "room",
    senderId,
    senderRhingSeed: senderDoc.data()?.rhingSeed ?? null,
    content,
    contentType: "call",
    callResult: result,
    callId,
    callStartedAt: missed ? null : params.startedAt,
    callDurationSeconds: missed ? null : params.durationSeconds,
    callIsVideo: params.isVideo,
    callJoinedUserIds: params.joinedUserIds ?? [],
    sentAt: FieldValue.serverTimestamp(),
    hiddenFor: [],
    readBy: [],
    isSpam: false,
    silent: false,
    reactions: {},
  });
  batch.update(roomRef, { lastMessageAt: FieldValue.serverTimestamp() });
  batch.update(parentRef, {
    lastMessageAt: FieldValue.serverTimestamp(),
    lastMessageSenderId: senderId,
    lastMessageContentType: "call",
    lastMessagePreview: content,
  });
  await batch.commit();
}

/**
 * 一対の通話が終わったら、発信者名義で通話の記録（つながった通話）か不在着信（不在・拒否・応答前の終了）を残す。
 * 応答時刻（`connectedAt`）が無い古いクライアントの通話は、時間なしの記録にする。
 */
export const onCallEnded = onDocumentUpdated(
  { document: "calls/{callId}", region: "asia-northeast1" },
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after) return;
    const terminal = ["ended", "declined", "missed"];
    if (terminal.includes(before.status) || !terminal.includes(after.status)) {
      return;
    }
    // 終了が書かれずに残り、`sweepStaleCalls`が片付けた通話には記録を書かない
    // （通話時間が分からず、途中で落ちた・過去の残骸のため）。
    if (after.staleEnded === true) return;
    const callerId = after.callerId as string | undefined;
    const calleeId = after.calleeId as string | undefined;
    const dmId = after.dmId as string | undefined;
    if (!callerId || !calleeId || !dmId) return;
    // ブロック中の相手との通話は、相手に悟らせないため記録しない。
    if (
      (await isBlockedBy(calleeId, callerId)) ||
      (await isBlockedBy(callerId, calleeId))
    ) {
      return;
    }
    const result = dmCallRecordResult(before.status, after.status);
    const answered = result === "completed";
    const connectedAt = after.connectedAt as Timestamp | undefined;
    const endedAt = (after.endedAt as Timestamp | undefined) ?? Timestamp.now();
    const durationSeconds =
      answered && connectedAt
        ? Math.max(0, Math.round((endedAt.toMillis() - connectedAt.toMillis()) / 1000))
        : null;
    await writeCallRecordMessage({
      isDm: true,
      conversationId: dmId,
      callId: event.params.callId,
      senderId: callerId,
      result,
      startedAt: connectedAt ?? null,
      durationSeconds,
      isVideo: after.isVideo === true,
      roomId: (after.roomId as string | undefined) ?? null,
      // つながった通話は、双方が出ていた。不在・拒否・取消は、受け手が出ていない。
      joinedUserIds: answered ? [callerId, calleeId] : [callerId],
    });
  },
);

/**
 * 広場の通話が終わったら、通話を始めた人の名義で記録を残す。始めた人以外が1人も入らなかった
 * 通話は不在着信。始めた人が広場のメンバーでなくなっていれば長の名義にする。
 * `joinedUserIds`を持たない古いクライアントの通話は、不在着信と決めつけず通話記録として扱う。
 */
export const recordGroupCallEnd = onDocumentUpdated(
  { document: "groupCalls/{groupCallId}", region: "asia-northeast1" },
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after) return;
    if (before.status !== "active" || after.status !== "ended") return;
    const groupId = after.groupId as string | undefined;
    const initiatorId = after.initiatorId as string | undefined;
    if (!groupId || !initiatorId) return;
    const groupDoc = await db.doc(`groups/${groupId}`).get();
    if (!groupDoc.exists) return;
    const group = groupDoc.data()!;
    const memberIds: string[] = Array.isArray(group.memberIds) ? group.memberIds : [];
    const senderId = memberIds.includes(initiatorId)
      ? initiatorId
      : (group.ownerId as string | undefined);
    if (!senderId) return;
    const createdAt = after.createdAt as Timestamp | undefined;
    const endedAt = (after.endedAt as Timestamp | undefined) ?? Timestamp.now();
    const result = groupCallRecordResult({
      joinedUserIds: after.joinedUserIds,
      initiatorId,
      createdAtMs: createdAt ? createdAt.toMillis() : null,
      endedAtMs: endedAt.toMillis(),
    });
    await writeCallRecordMessage({
      isDm: false,
      conversationId: groupId,
      callId: event.params.groupCallId,
      senderId,
      result,
      startedAt: createdAt ?? null,
      durationSeconds: createdAt
        ? Math.max(0, Math.round((endedAt.toMillis() - createdAt.toMillis()) / 1000))
        : null,
      isVideo: after.isVideo === true,
      roomId: (after.roomId as string | undefined) ?? null,
      joinedUserIds: Array.isArray(after.joinedUserIds)
        ? (after.joinedUserIds as string[])
        : null,
    });
  },
);

/**
 * 終了が書かれないまま残った通話を片付ける（2026-11-17）。端末が落ちる・圏外になる等で、
 * クライアントが終了を書けなかった通話は、記録も出ないため。一対は呼び出し中のまま
 * 一定時間が過ぎたものを`missed`に、広場はハートビートが途絶えた通話を`ended`にする
 * （どちらも更新が`onCallEnded`・`recordGroupCallEnd`を起こして記録が書かれる）。
 */
export const sweepStaleCalls = onSchedule(
  { schedule: "every 5 minutes", region: "asia-northeast1" },
  async () => {
    const now = Date.now();
    const ringing = await db
      .collection("calls")
      .where("status", "==", "ringing")
      .get();
    for (const doc of ringing.docs) {
      const createdAt = doc.data().createdAt as Timestamp | undefined;
      if (!createdAt || now - createdAt.toMillis() < DM_CALL_STALE_RINGING_MS) {
        continue;
      }
      await doc.ref.update({ status: "missed", endedAt: FieldValue.serverTimestamp() });
    }

    // 一対の通話で、終了が書かれずに`active`のまま残ったものを終わらせる（2026-11-17）。
    // ハートビート（`callerSeenAt`・`calleeSeenAt`、15秒ごと）が90秒途絶えた、または
    // ハートビートが無いまま3時間を超えたもの。通話の記録は書かない（`staleEnded`）。
    const activeOneToOne = await db
      .collection("calls")
      .where("status", "==", "active")
      .get();
    for (const doc of activeOneToOne.docs) {
      const data = doc.data();
      const seen = [data.callerSeenAt, data.calleeSeenAt]
        .filter((t): t is Timestamp => t instanceof Timestamp)
        .map((t) => t.toMillis());
      let lastAlive: number | null = null;
      let stale = false;
      if (seen.length > 0) {
        lastAlive = Math.max(...seen);
        stale = now - lastAlive > DM_CALL_HEARTBEAT_STALE_MS;
      } else {
        const since = (data.connectedAt ?? data.createdAt) as Timestamp | undefined;
        if (!since) continue;
        lastAlive = since.toMillis();
        stale = now - lastAlive > DM_CALL_NO_HEARTBEAT_MAX_MS;
      }
      if (!stale) continue;
      await doc.ref.update({
        status: "ended",
        endedAt: Timestamp.fromMillis(lastAlive),
        staleEnded: true,
      });
    }

    const active = await db
      .collection("groupCalls")
      .where("status", "==", "active")
      .get();
    for (const doc of active.docs) {
      const data = doc.data();
      const createdAt = data.createdAt as Timestamp | undefined;
      if (!createdAt || now - createdAt.toMillis() < GROUP_CALL_ABANDONED_GRACE_MS) {
        continue;
      }
      const participants = await doc.ref.collection("participants").get();
      const live = participants.docs.filter((p) => {
        const lastSeenAt = p.data().lastSeenAt as Timestamp | undefined;
        if (!lastSeenAt) return true;
        return now - lastSeenAt.toMillis() <= GROUP_CALL_PRESENCE_STALE_MS;
      });
      if (live.length > 0) continue;
      await doc.ref.update({ status: "ended", endedAt: FieldValue.serverTimestamp() });
      const pointer = db.doc(`groupActiveCallPointers/${data.groupId}`);
      const pointerDoc = await pointer.get();
      if (pointerDoc.data()?.activeCallId === doc.id) {
        await pointer.update({ activeCallId: null });
      }
    }
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

/** サムネイルの長辺の上限（px）。4Kの動画から原寸のJPEGを作らず、一覧・通知に十分な
 * 大きさにする（2026-11-08）。 */
const THUMBNAIL_MAX_SIDE = 960;

/** ダウンロードして処理してよい動画の上限（バイト）。一時領域がメモリ上の為、これを
 * 超える動画は、URLから読めない時にはサムネイルを作らない（2026-11-08）。 */
const THUMBNAIL_DOWNLOAD_LIMIT_BYTES = 400 * 1024 * 1024;

/**
 * 動画の1コマをJPEGのサムネイルとして[outPath]へ書く（2026-11-08）。以前は動画全体を
 * メモリ上の一時領域へダウンロードしていた為、メモリ1GiBでは1GB超の動画（4Kのデジカメ
 * 動画など）で失敗し、サムネイルが付かなかった。今は、アップロード時にクライアントが付けた
 * ダウンロードトークンのURLを`ffmpeg`へ直接渡し、`-ss`で先頭付近へ飛んで必要な部分だけを
 * 読む（`moov`が先頭にある動画なら数MBで済む）。トークンが無い、又はURLから読めなかった
 * 時だけ、小さい動画に限りダウンロードして処理する。出力は長辺[THUMBNAIL_MAX_SIDE]px以下。
 * 作れたら`true`。
 */
async function renderVideoThumbnail(opts: {
  bucketName: string;
  filePath: string;
  sizeBytes: number;
  metadata: Record<string, unknown> | undefined;
  outPath: string;
  tmpKey: string;
}): Promise<boolean> {
  const { bucketName, filePath, sizeBytes, metadata, outPath, tmpKey } = opts;
  const scale =
    `scale='if(gt(iw,ih),min(${THUMBNAIL_MAX_SIDE},iw),-2)'` +
    `:'if(gt(iw,ih),-2,min(${THUMBNAIL_MAX_SIDE},ih))'`;
  const grab = (input: string, timestamp: string) =>
    new Promise<void>((resolve, reject) => {
      ffmpeg(input)
        .inputOptions(["-ss", timestamp])
        .outputOptions(["-frames:v", "1", "-q:v", "3", "-vf", scale])
        .output(outPath)
        .on("end", () => resolve())
        .on("error", (err: Error) => reject(err))
        .run();
    });
  // 1秒付近の1コマ（冒頭は暗転・フェードインで黒くなりやすい為、アプリ側
  // `VideoThumbnail`の表示位置と同じ）。1秒に満たない短い動画ではコマが出ない
  // （エラーにもならない）ので、出力が無ければ先頭付近（0.1秒）で撮り直す。
  const grabBoth = async (input: string): Promise<boolean> => {
    for (const timestamp of ["1", "0.1"]) {
      try {
        await grab(input, timestamp);
      } catch (err) {
        logger.warn(`動画サムネイル: ${timestamp}秒位置で失敗 (${filePath})`, err);
      }
      if (fs.existsSync(outPath)) return true;
    }
    return false;
  };

  const token = String(metadata?.["firebaseStorageDownloadTokens"] ?? "")
    .split(",")[0]
    .trim();
  if (token) {
    const url =
      `https://firebasestorage.googleapis.com/v0/b/${bucketName}/o/` +
      `${encodeURIComponent(filePath)}?alt=media&token=${token}`;
    if (await grabBoth(url)) return true;
    logger.warn(`動画サムネイル: URLから読めませんでした (${filePath})`);
  }
  if (sizeBytes > THUMBNAIL_DOWNLOAD_LIMIT_BYTES) {
    logger.warn(
      `動画サムネイル: 大きすぎてダウンロードできないので作りません (${filePath}, ${sizeBytes}B)`,
    );
    return false;
  }
  const tmpVideoPath = path.join(
    os.tmpdir(),
    `${tmpKey}-src${path.extname(filePath)}`,
  );
  try {
    await getStorage()
      .bucket(bucketName)
      .file(filePath)
      .download({ destination: tmpVideoPath });
    return await grabBoth(tmpVideoPath);
  } finally {
    if (fs.existsSync(tmpVideoPath)) fs.unlinkSync(tmpVideoPath);
  }
}

/**
 * 動画メッセージのアップロード完了時に1フレーム抽出してサムネイル画像を
 * 生成し、Storageへ保存した上でメッセージの`fileMetadata.thumbnailUrl`に
 * 記録する（プッシュ通知のプレビュー画像用、2026-08-31追加）。
 * `lib/utils/attachment_upload.dart`が保存する`dmFiles/{dmId}/{messageId}.ext`・
 * `groupFiles/{groupId}/{messageId}.ext`という規約に依存している。複数添付
 * （`contentType: 'multi'`、2026-10-16）は`.../{messageId}/{index}.ext`の
 * 4階層で保存され、`attachments[index].thumbnailUrl`へ記録する。
 */
export const generateVideoThumbnail = onObjectFinalized(
  { region: "asia-northeast1", memory: "1GiB", timeoutSeconds: 120 },
  async (event) => {
    const filePath = event.data.name;
    const contentType = event.data.contentType;
    if (!filePath || !contentType?.startsWith("video/")) return;
    if (filePath.includes("_thumb.") || filePath.includes("_play.")) return; // 生成物自身の再帰防止
    // アルバムの動画（アップロード・メッセージからのコピー）は別の記録先なので別処理。
    if (filePath.startsWith("albumFiles/")) {
      await generateAlbumVideoThumbnail(
        event.data.bucket,
        filePath,
        Number(event.data.size),
        event.data.metadata,
      );
      return;
    }
    if (!filePath.startsWith("dmFiles/") && !filePath.startsWith("groupFiles/")) {
      return;
    }

    const segments = filePath.split("/");
    if (segments.length !== 3 && segments.length !== 4) return;
    const prefix = segments[0];
    const parentId = segments[1];
    const fileName = segments[segments.length - 1];
    // 4階層は複数添付: {prefix}/{parentId}/{messageId}/{index}.ext
    const isMulti = segments.length === 4;
    const messageId = isMulti
      ? segments[2]
      : fileName.replace(/\.[^.]+$/, "");
    const attachmentIndex = isMulti
      ? Number(fileName.replace(/\.[^.]+$/, ""))
      : -1;
    if (isMulti && !Number.isInteger(attachmentIndex)) return;

    const bucket = getStorage().bucket(event.data.bucket);
    const tmpThumbFileName = `${messageId}-${attachmentIndex}-thumb.jpg`;
    const tmpThumbPath = path.join(os.tmpdir(), tmpThumbFileName);
    const rendered = await renderVideoThumbnail({
      bucketName: event.data.bucket,
      filePath,
      sizeBytes: Number(event.data.size),
      metadata: event.data.metadata,
      outPath: tmpThumbPath,
      tmpKey: `${messageId}-${attachmentIndex}`,
    });
    if (!rendered) return;

    const thumbStoragePath = isMulti
      ? `${prefix}/${parentId}/${messageId}/${attachmentIndex}_thumb.jpg`
      : `${prefix}/${parentId}/${messageId}_thumb.jpg`;
    const downloadToken = randomUUID();
    await bucket.upload(tmpThumbPath, {
      destination: thumbStoragePath,
      metadata: {
        contentType: "image/jpeg",
        metadata: { firebaseStorageDownloadTokens: downloadToken },
      },
    });
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
    // メッセージはアップロード完了の後に書かれる（複数添付は全ファイルを上げ終えて
    // から）ため、サムネイル生成の方が早く終わることがある。単一動画でも同じで、
    // 見つからずにサムネイルが付かない事例があった（2026-10-16）。見つかるまで
    // 最大約20秒待つ。
    let messageRef = await findMessageRef(topCollection, parentId, messageId);
    for (let i = 0; i < 10 && !messageRef; i++) {
      await new Promise((resolve) => setTimeout(resolve, 2000));
      messageRef = await findMessageRef(topCollection, parentId, messageId);
    }
    if (!messageRef) {
      logger.warn(`動画サムネイル生成: メッセージが見つかりません (${filePath})`);
      return;
    }
    if (!isMulti) {
      await messageRef.update({ "fileMetadata.thumbnailUrl": thumbnailUrl });
      logger.info(`動画サムネイル記録: ${messageRef.path}`);
      return;
    }
    // 配列の要素は点記法で更新できないため、トランザクションで差し替える。
    await db.runTransaction(async (tx) => {
      const snap = await tx.get(messageRef!);
      const attachments = (snap.get("attachments") ?? []) as Array<
        Record<string, unknown>
      >;
      if (!attachments[attachmentIndex]) {
        logger.warn(
          `動画サムネイル: attachments[${attachmentIndex}]が無い (${messageRef!.path}, 件数${attachments.length})`,
        );
        return;
      }
      attachments[attachmentIndex] = {
        ...attachments[attachmentIndex],
        thumbnailUrl,
      };
      const update: Record<string, unknown> = { attachments };
      if (attachmentIndex === 0) {
        update["fileMetadata.thumbnailUrl"] = thumbnailUrl;
      }
      tx.update(messageRef!, update);
    });
    logger.info(`動画サムネイル記録: ${messageRef.path} [${attachmentIndex}]`);
  },
);

/**
 * アルバムの動画（`albumFiles/{dm|group}/{会話id}/{寄合id}/{albumId}/{itemId}.ext`）の
 * サムネイル（動画の1秒付近の1コマ）を生成し、アイテムの`thumbnailUrl`へ記録する
 * （2026-11-07）。メッセージの動画（[generateVideoThumbnail]の本体）と同じ方式で、
 * ブラウザで動画の先頭コマを取れない（黒く見える）場合の表示用。アイテムはファイルの
 * アップロード後に作られるので、見つかるまで最大約20秒待つ。アルバムの表紙が
 * この動画なら、表紙の画像もサムネイルにする。
 */
async function generateAlbumVideoThumbnail(
  bucketName: string,
  filePath: string,
  sizeBytes: number,
  metadata: Record<string, unknown> | undefined,
): Promise<void> {
  const segments = filePath.split("/");
  if (segments.length !== 6) return;
  const [, scope, conversationId, roomId, albumId, fileName] = segments;
  if (scope !== "dm" && scope !== "group") return;
  const itemId = fileName.replace(/\.[^.]+$/, "");
  const bucket = getStorage().bucket(bucketName);
  const tmpKey = `album-${itemId}`;
  const tmpThumbFileName = `${tmpKey}-thumb.jpg`;
  const tmpThumbPath = path.join(os.tmpdir(), tmpThumbFileName);

  try {
    const rendered = await renderVideoThumbnail({
      bucketName,
      filePath,
      sizeBytes,
      metadata,
      outPath: tmpThumbPath,
      tmpKey,
    });
    if (!rendered) return;

    const thumbStoragePath = `${segments.slice(0, 5).join("/")}/${itemId}_thumb.jpg`;
    const downloadToken = randomUUID();
    await bucket.upload(tmpThumbPath, {
      destination: thumbStoragePath,
      metadata: {
        contentType: "image/jpeg",
        metadata: { firebaseStorageDownloadTokens: downloadToken },
      },
    });
    const thumbnailUrl =
      `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/` +
      `${encodeURIComponent(thumbStoragePath)}?alt=media&token=${downloadToken}`;

    const top = scope === "dm" ? "directMessages" : "groups";
    const albumRef = db.doc(`${top}/${conversationId}/rooms/${roomId}/albums/${albumId}`);
    const itemRef = albumRef.collection("items").doc(itemId);
    let item = await itemRef.get();
    for (let i = 0; i < 10 && !item.exists; i++) {
      await new Promise((resolve) => setTimeout(resolve, 2000));
      item = await itemRef.get();
    }
    if (!item.exists) {
      logger.warn(`アルバム動画サムネイル: アイテムが見つかりません (${filePath})`);
      return;
    }
    await itemRef.update({ thumbnailUrl });
    const album = await albumRef.get();
    if (album.get("coverItemId") === itemId) {
      await albumRef.update({ coverThumbnailUrl: thumbnailUrl });
    }
    logger.info(`アルバム動画サムネイル記録: ${itemRef.path}`);
  } finally {
    if (fs.existsSync(tmpThumbPath)) fs.unlinkSync(tmpThumbPath);
  }
}

/**
 * 重い動画（高ビットレート・4Kなど）の再生用の軽い版を作る（2026-11-08）。
 * 動画のアップロード完了時に`ffmpeg -i`で映像の情報を調べ、[needsPlaybackVersion]が
 * 真なら、短辺1080px以下・約8Mbps以下のH.264＋AAC（`faststart`）を元のファイルの横に
 * `_play.mp4`として保存し、メッセージ・複数添付・アルバム項目へ`playbackPath`（真の情報）と
 * `playbackUrl`（併記）を記録する。クライアントのビューアはこれがあれば再生に使い、
 * ダウンロード・共有・転送は元のファイルのまま。変換の前や、軽い動画では記録されず、
 * 従来どおり元の動画を再生する。保存先の規約は[generateVideoThumbnail]と同じ
 * （`dmFiles|groupFiles/{id}/{messageId}.ext`、複数添付は`.../{messageId}/{index}.ext`、
 * アルバムは`albumFiles/{dm|group}/{会話id}/{寄合id}/{albumId}/{itemId}.ext`）。
 *
 * 変換は時間とメモリを使う（Cloud Functionsの一時領域はメモリ上）ので、メモリ8GiB・
 * CPU4・同時1件に制限する。イベント起動の関数は最大540秒なので、長さが
 * [kMaxPlaybackSourceSeconds]（10分）を超える動画は作らず、変換が
 * [kPlaybackTranscodeBudgetMs]を超えたら打ち切る（その場合は元の動画のまま）。
 */
export const generatePlaybackVideo = onObjectFinalized(
  {
    region: "asia-northeast1",
    memory: "8GiB",
    cpu: 4,
    // イベント起動の関数は最大540秒。変換はこの中に収める（下の長さ制限と打ち切りを参照）。
    timeoutSeconds: 540,
    concurrency: 1,
    maxInstances: 3,
  },
  async (event) => {
    const filePath = event.data.name;
    const contentType = event.data.contentType;
    if (!filePath || !contentType?.startsWith("video/")) return;
    if (filePath.includes("_thumb.") || filePath.includes("_play.")) return;
    const segments = filePath.split("/");
    const prefix = segments[0];
    // 保存先ごとに、記録先（メッセージ／複数添付／アルバム項目）を決める。
    type Target =
      | { kind: "message"; top: string; parentId: string; messageId: string }
      | {
          kind: "multi";
          top: string;
          parentId: string;
          messageId: string;
          index: number;
        }
      | {
          kind: "album";
          top: string;
          conversationId: string;
          roomId: string;
          albumId: string;
          itemId: string;
        };
    let target: Target;
    if ((prefix === "dmFiles" || prefix === "groupFiles") && segments.length === 3) {
      target = {
        kind: "message",
        top: prefix === "dmFiles" ? "directMessages" : "groups",
        parentId: segments[1],
        messageId: segments[2].replace(/\.[^.]+$/, ""),
      };
    } else if (
      (prefix === "dmFiles" || prefix === "groupFiles") &&
      segments.length === 4
    ) {
      const index = Number(segments[3].replace(/\.[^.]+$/, ""));
      if (!Number.isInteger(index)) return;
      target = {
        kind: "multi",
        top: prefix === "dmFiles" ? "directMessages" : "groups",
        parentId: segments[1],
        messageId: segments[2],
        index,
      };
    } else if (prefix === "albumFiles" && segments.length === 6) {
      const [, scope, conversationId, roomId, albumId, fileName] = segments;
      if (scope !== "dm" && scope !== "group") return;
      target = {
        kind: "album",
        top: scope === "dm" ? "directMessages" : "groups",
        conversationId,
        roomId,
        albumId,
        itemId: fileName.replace(/\.[^.]+$/, ""),
      };
    } else {
      return;
    }

    // 一時領域がメモリ上の為、極端に大きいファイルは扱わない（サーバー経由は2GBまで）。
    const sizeBytes = Number(event.data.size);
    if (sizeBytes > 2.5 * 1024 * 1024 * 1024) {
      logger.warn(`再生用の動画: 大きすぎるので作りません (${filePath}, ${sizeBytes}B)`);
      return;
    }

    const bucket = getStorage().bucket(event.data.bucket);
    const key = filePath.replace(/[^A-Za-z0-9]/g, "_");
    const tmpSrc = path.join(os.tmpdir(), `${key}-src${path.extname(filePath)}`);
    const tmpOut = path.join(os.tmpdir(), `${key}-play.mp4`);
    try {
      await bucket.file(filePath).download({ destination: tmpSrc });
      const info = parseFfmpegInfo(await ffmpegInfoOutput(tmpSrc));
      if (!needsPlaybackVersion(info)) {
        logger.info(`再生用の動画: 軽いので作りません (${filePath})`, info);
        return;
      }
      // 関数の制限時間（540秒）に収まらない長い動画は作らない。変換中の打ち切り
      // （下のタイマー）はそれでも間に合わなかった時の保険。
      if (info?.durationSec != null && info.durationSec > kMaxPlaybackSourceSeconds) {
        logger.warn(
          `再生用の動画: 長すぎるので作りません (${filePath}, ${info.durationSec}秒)`,
        );
        return;
      }
      logger.info(`再生用の動画: 変換を始めます (${filePath})`, info);
      try {
        await new Promise<void>((resolve, reject) => {
          const command = ffmpeg(tmpSrc)
            .videoFilters(kPlaybackScaleFilter)
            .outputOptions(kPlaybackOutputOptions)
            .output(tmpOut)
            .on("end", () => {
              clearTimeout(watchdog);
              resolve();
            })
            .on("error", (err: Error) => {
              clearTimeout(watchdog);
              reject(err);
            });
          // 制限時間の前に打ち切る（アップロードと記録の時間を残す）。
          const watchdog = setTimeout(
            () => command.kill("SIGKILL"),
            kPlaybackTranscodeBudgetMs,
          );
          command.run();
        });
      } catch (err) {
        logger.warn(`再生用の動画: 変換できませんでした (${filePath})`, err);
        return;
      }

      const playbackPath = playbackStoragePath(filePath);
      const downloadToken = randomUUID();
      await bucket.upload(tmpOut, {
        destination: playbackPath,
        metadata: {
          contentType: "video/mp4",
          metadata: { firebaseStorageDownloadTokens: downloadToken },
        },
      });
      const playbackUrl =
        `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/` +
        `${encodeURIComponent(playbackPath)}?alt=media&token=${downloadToken}`;
      const fields = { playbackPath, playbackUrl };

      // 記録先のドキュメントは、アップロードの後に作られることがある（サムネイルと同じ）。
      // 見つかるまで最大約20秒待つ。
      const waitFor = async <T>(find: () => Promise<T | null>): Promise<T | null> => {
        let found = await find();
        for (let i = 0; i < 10 && !found; i++) {
          await new Promise((resolve) => setTimeout(resolve, 2000));
          found = await find();
        }
        return found;
      };

      if (target.kind === "album") {
        const itemRef = db
          .collection(target.top)
          .doc(target.conversationId)
          .collection("rooms")
          .doc(target.roomId)
          .collection("albums")
          .doc(target.albumId)
          .collection("items")
          .doc(target.itemId);
        const found = await waitFor(async () => ((await itemRef.get()).exists ? itemRef : null));
        if (!found) {
          logger.warn(`再生用の動画: アルバム項目が見つかりません (${filePath})`);
          return;
        }
        await itemRef.update(fields);
        logger.info(`再生用の動画を記録: ${itemRef.path}`);
        return;
      }

      const messageTarget = target;
      const messageRef = await waitFor(() =>
        findMessageRef(
          messageTarget.top as "directMessages" | "groups",
          messageTarget.parentId,
          messageTarget.messageId,
        ),
      );
      if (!messageRef) {
        logger.warn(`再生用の動画: メッセージが見つかりません (${filePath})`);
        return;
      }
      if (target.kind === "message") {
        await messageRef.update({
          "fileMetadata.playbackPath": playbackPath,
          "fileMetadata.playbackUrl": playbackUrl,
        });
        logger.info(`再生用の動画を記録: ${messageRef.path}`);
        return;
      }
      const attachmentIndex = target.index;
      await db.runTransaction(async (tx) => {
        const snap = await tx.get(messageRef);
        const attachments = (snap.get("attachments") ?? []) as Array<
          Record<string, unknown>
        >;
        if (!attachments[attachmentIndex]) return;
        attachments[attachmentIndex] = { ...attachments[attachmentIndex], ...fields };
        const update: Record<string, unknown> = { attachments };
        if (attachmentIndex === 0) {
          update["fileMetadata.playbackPath"] = playbackPath;
          update["fileMetadata.playbackUrl"] = playbackUrl;
        }
        tx.update(messageRef, update);
      });
      logger.info(`再生用の動画を記録: ${messageRef.path} [${attachmentIndex}]`);
    } finally {
      for (const tmp of [tmpSrc, tmpOut]) {
        if (fs.existsSync(tmp)) fs.unlinkSync(tmp);
      }
    }
  },
);

/** `ffmpeg -i <file>`の標準エラー出力（映像・音声ストリームの情報）を返す。出力先が
 * 無い`ffmpeg -i`は常に非0で終わるので、終了コードは見ない。 */
function ffmpegInfoOutput(file: string): Promise<string> {
  return new Promise((resolve, reject) => {
    if (!ffmpegPath) {
      reject(new Error("ffmpegが見つかりません"));
      return;
    }
    const child = spawn(ffmpegPath, ["-hide_banner", "-i", file]);
    let stderr = "";
    child.stderr.on("data", (chunk: Buffer) => {
      stderr += chunk.toString();
    });
    child.on("error", reject);
    child.on("close", () => resolve(stderr));
  });
}

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

/**
 * 友達になった2人の、friends双方・一対（directMessages）・メインの寄合を作る
 * （Admin SDK、ルールを経由しない）。相互申請の即時承認（`sendFriendRequest`）と、
 * 承認（`respondFriendRequest`）で共有する。残骸があっても失敗しないよう、
 * friendsは上書き、一対と寄合は既にあれば作り直さない（2026-11-17）。
 * [extraWrites]は同じバッチに載せたい書き込み（申請の`accepted`への更新）。
 */
async function createFriendship(
  userAId: string,
  userARhingSeed: string,
  userBId: string,
  userBRhingSeed: string,
  extraWrites?: (batch: FirebaseFirestore.WriteBatch) => void,
): Promise<void> {
  const dmId = pairId(userAId, userBId);
  const dmRef = db.collection("directMessages").doc(dmId);
  const [dmDoc, existingRooms] = await Promise.all([
    dmRef.get(),
    dmRef.collection("rooms").limit(1).get(),
  ]);
  const batch = db.batch();
  extraWrites?.(batch);
  batch.set(
    db.collection("users").doc(userAId).collection("friends").doc(userBId),
    { friendRhingSeed: userBRhingSeed, addedAt: FieldValue.serverTimestamp() },
  );
  batch.set(
    db.collection("users").doc(userBId).collection("friends").doc(userAId),
    { friendRhingSeed: userARhingSeed, addedAt: FieldValue.serverTimestamp() },
  );
  if (!dmDoc.exists) {
    batch.set(dmRef, {
      participants: [userAId, userBId],
      participantRhingSeeds: { [userAId]: userARhingSeed, [userBId]: userBRhingSeed },
      readReceiptsEnabled: true,
      roomsEnabled: false,
    });
  }
  if (existingRooms.empty) {
    batch.set(dmRef.collection("rooms").doc(), {
      dmId,
      name: "メイン",
      participants: [userAId, userBId],
      createdAt: FieldValue.serverTimestamp(),
      pinnedMessageIds: [],
    });
  }
  await batch.commit();
}

/**
 * 友達申請の承認（宛先本人のみ）。以前はクライアントが「申請をacceptedへ」→「friends・
 * 一対・寄合を作成」の2回に分けて書いていて、後者がルールで拒否されると、申請だけが
 * 保留から消えて友達にならなかった（2026-11-17）。ここで1回のバッチにまとめる。
 * 拒否はクライアントの直接更新のまま。
 */
export const respondFriendRequest = onCall(
  { region: "asia-northeast1" },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }
    const requestId = request.data?.requestId;
    if (typeof requestId !== "string" || !requestId) {
      throw new HttpsError("invalid-argument", "requestIdが必要です");
    }
    const ref = db.collection("friendRequests").doc(requestId);
    const doc = await ref.get();
    if (!doc.exists) {
      throw new HttpsError("not-found", "友達申請が見つかりません");
    }
    const data = doc.data()!;
    const fromUserId: unknown = data.fromUserId;
    const toUserId: unknown = data.toUserId;
    if (typeof fromUserId !== "string" || typeof toUserId !== "string") {
      throw new HttpsError("failed-precondition", "友達申請の内容が不正です");
    }
    if (toUserId !== uid) {
      throw new HttpsError("permission-denied", "宛先の本人だけが承認できます");
    }
    if (data.status === "accepted") {
      // 承認済みでも友達が作られていない（以前の不具合の残り）場合は、作り直す。
      const stillFriends = (
        await db.collection("users").doc(toUserId).collection("friends").doc(fromUserId).get()
      ).exists;
      if (stillFriends) return;
    } else if (data.status !== "pending") {
      throw new HttpsError("failed-precondition", "この友達申請は承認できません");
    }
    // Rhing Seedは、申請に書かれた値ではなく、両者の`users`の値を使う（`sendFriendRequest`と同じ）。
    const [fromUser, toUser] = await Promise.all([
      db.collection("users").doc(fromUserId).get(),
      db.collection("users").doc(toUserId).get(),
    ]);
    const fromRhingSeed: unknown = fromUser.data()?.rhingSeed;
    const toRhingSeed: unknown = toUser.data()?.rhingSeed;
    if (typeof fromRhingSeed !== "string" || typeof toRhingSeed !== "string") {
      throw new HttpsError("not-found", "ユーザーが見つかりません");
    }
    await createFriendship(fromUserId, fromRhingSeed, toUserId, toRhingSeed, (batch) => {
      batch.update(ref, {
        status: "accepted",
        respondedAt: FieldValue.serverTimestamp(),
      });
    });
  },
);

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
    const claimedFromRhingSeed = request.data?.fromRhingSeed ?? request.data?.fromRhingId;
    const toUserId = request.data?.toUserId;
    const claimedToRhingSeed = request.data?.toRhingSeed ?? request.data?.toRhingId;
    const rawMessage = request.data?.message;
    if (
      typeof fromUserId !== "string" ||
      typeof claimedFromRhingSeed !== "string" ||
      typeof toUserId !== "string" ||
      typeof claimedToRhingSeed !== "string"
    ) {
      throw new HttpsError("invalid-argument", "パラメータが不正です");
    }
    if (fromUserId !== uid) {
      throw new HttpsError("permission-denied", "本人としてのみ送信できます");
    }
    if (toUserId === fromUserId) {
      throw new HttpsError("invalid-argument", "自分自身には送信できません");
    }
    // Rhing Seedは、クライアントから渡された値を信用せず、両者の`users`の値を使う
    // （他人の・予約語のSeedを名乗る友達申請・友達・一対の記録を防ぐ、2026-11-16）。
    const [fromSeedUser, toSeedUser] = await Promise.all([
      db.collection("users").doc(fromUserId).get(),
      db.collection("users").doc(toUserId).get(),
    ]);
    const fromRhingSeed: unknown = fromSeedUser.data()?.rhingSeed;
    const toRhingSeed: unknown = toSeedUser.data()?.rhingSeed;
    if (typeof fromRhingSeed !== "string" || typeof toRhingSeed !== "string") {
      throw new HttpsError("not-found", "ユーザーが見つかりません");
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

    // 相互承認時のfriends/directMessages/dmRoom作成は、モジュールレベルの
    // `createFriendship`（承認の`respondFriendRequest`と共通）を使う。

    // 宛先が送信者をブロックしている場合は、何も作らず成功と同じ応答で終える
    // （相手にブロックを悟らせない、2026-10-11）。試行はレート制限に数え済み。
    if (await isBlockedBy(toUserId, fromUserId)) return;

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
    await setAuthDisabled(userId, true);
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
    await Promise.all(snapshot.docs.map((doc) => setAuthDisabled(doc.id, false)));
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

/**
 * リンクプレビュー用の取得中継（2026-10-14）。Cloudflare WorkerからはpixivとInstagram
 * （一部）がIPで弾かれるため、Worker側がこの関数（Google CloudのIP）経由で取り直す。
 * 誰でも呼べる公開エンドポイントのため、取得先は許可ホスト（pixiv・Instagram）に
 * 限定し、リダイレクトも許可ホスト内だけ追従する。応答は`{ status, text }`で、
 * 解析（OGP・pixivのajax）はWorker側が行う。
 */
export const urlFetchRelay = onRequest(
  { region: "asia-northeast1", memory: "256MiB", timeoutSeconds: 15, cors: true },
  async (req, res) => {
    if (req.method !== "GET") {
      res.status(405).send("GET only");
      return;
    }
    const target = parseAllowedUrl(req.query.url);
    if (!target) {
      res.status(400).json({ error: "url not allowed" });
      return;
    }
    const headers: Record<string, string> = {
      "User-Agent": resolveUserAgent(req.query.ua),
      "Accept-Language": "ja,en;q=0.8",
    };
    const referer = resolveReferer(req.query.referer);
    if (referer) headers.Referer = referer;
    try {
      let current = target;
      let response: Response | null = null;
      for (let hop = 0; hop < 3; hop++) {
        response = await fetch(current, {
          headers,
          redirect: "manual",
          signal: AbortSignal.timeout(8000),
        });
        const location = response.headers.get("location");
        if (response.status >= 300 && response.status < 400 && location) {
          const next = parseAllowedUrl(new URL(location, current).toString());
          if (!next) break;
          current = next;
          continue;
        }
        break;
      }
      const body = response ? await response.text() : "";
      res.set("Cache-Control", "no-store");
      res.status(200).json({
        status: response?.status ?? 0,
        text: body.slice(0, 2 * 1024 * 1024),
      });
    } catch (err) {
      logger.warn("取得中継に失敗しました:", String(err));
      res.status(200).json({ status: 0, text: "" });
    }
  },
);

// ---------------------------------------------------------------------
// 住人による通報（メッセージ・住人・広場、2026-11-22追加）。Apple App Reviewの
// ガイドライン1.2（ユーザー生成コンテンツ）が求める通報の導線と、運営の処理の記録。
// 通報は`reports/{reportId}`に保存し、書き込みはここ（Admin SDK）だけ、クライアント
// からは読み書きできない（firestore.rulesに許可が無く既定で拒否）。純粋なロジックは
// `reports.ts`（単体テストあり）。
// ---------------------------------------------------------------------

/** 通報の文書idを、通報者と対象から決める（同じ通報者が同じ対象を重ねて通報できない）。 */
function reportDocId(reporterId: string, targetKey: string): string {
  const digest = createHash("sha256").update(targetKey).digest("hex").slice(0, 32);
  return `${reporterId}_${digest}`;
}

/**
 * 通報する（ログイン済みの住人）。対象は、メッセージ・住人・広場のいずれか。
 * メッセージの場合は、対象と前後のメッセージをサーバーが複写して証拠にする
 * （クライアントの申告は信用しない）。同じ対象を同じ人が重ねて通報した場合は、
 * 新しく作らず`alreadyReported: true`を返す。
 */
export const submitReport = onCall(
  { region: "asia-northeast1" },
  async (request) => {
    const reporterId = request.auth?.uid;
    if (!reporterId) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }
    const parsed = parseReportInput(request.data);
    if (!parsed.ok) {
      throw new HttpsError("invalid-argument", parsed.reason);
    }
    const input = parsed.input;

    // 通報者の情報（呼び名ではなく、Rhing Seedだけを控える）。
    const reporterDoc = await db.collection("users").doc(reporterId).get();
    if (!reporterDoc.exists) {
      throw new HttpsError("failed-precondition", "アカウントが見つかりません");
    }
    const reporterSeed: string | null = reporterDoc.data()?.rhingSeed ?? null;

    const docId = reportDocId(reporterId, reportTargetKey(input));
    const reportRef = db.collection("reports").doc(docId);
    if ((await reportRef.get()).exists) {
      return { alreadyReported: true };
    }

    // 乱用の抑止: 24時間の通報の件数。
    const recent = await db
      .collection("reports")
      .where("reporterId", "==", reporterId)
      .limit(100)
      .get();
    const createdAtMillis = recent.docs
      .map((d) => (d.data().createdAt as Timestamp | undefined)?.toMillis())
      .filter((t): t is number => typeof t === "number");
    if (isOverDailyLimit(createdAtMillis, Date.now())) {
      throw new HttpsError(
        "resource-exhausted",
        "通報の回数が多すぎます。しばらくしてからもう一度お試しください",
      );
    }

    let targetUserId: string | null = null;
    let targetSeed: string | null = null;
    let evidence: Record<string, unknown> = {};

    if (input.targetType === "user") {
      if (input.targetUserId === reporterId) {
        throw new HttpsError("invalid-argument", "自分は通報できません");
      }
      const target = await db.collection("users").doc(input.targetUserId!).get();
      if (!target.exists) {
        throw new HttpsError("not-found", "住人が見つかりません");
      }
      targetUserId = input.targetUserId!;
      targetSeed = target.data()?.rhingSeed ?? null;
    } else if (input.targetType === "group") {
      const group = await db.collection("groups").doc(input.groupId!).get();
      const g = group.data();
      if (!group.exists || !g) {
        throw new HttpsError("not-found", "広場が見つかりません");
      }
      const memberIds: string[] = g.memberIds ?? [];
      if (!memberIds.includes(reporterId)) {
        throw new HttpsError("permission-denied", "参加している広場だけ通報できます");
      }
      if (g.ownerId === reporterId) {
        throw new HttpsError("invalid-argument", "自分が長の広場は通報できません");
      }
      targetUserId = typeof g.ownerId === "string" ? g.ownerId : null;
      evidence = {
        group: {
          groupId: group.id,
          name: typeof g.name === "string" ? g.name : "",
          ownerId: targetUserId,
          memberCount: memberIds.length,
        },
      };
    } else {
      // メッセージ。会話の参加者だけが通報できる。
      const isDm = input.dmId !== undefined;
      const conversationRef = db
        .collection(isDm ? "directMessages" : "groups")
        .doc((isDm ? input.dmId : input.groupId)!);
      const conversation = await conversationRef.get();
      const c = conversation.data();
      if (!conversation.exists || !c) {
        throw new HttpsError("not-found", "会話が見つかりません");
      }
      const members: string[] = (isDm ? c.participants : c.memberIds) ?? [];
      if (!members.includes(reporterId)) {
        throw new HttpsError("permission-denied", "参加している会話だけ通報できます");
      }
      const messagesRef = conversationRef
        .collection("rooms")
        .doc(input.roomId!)
        .collection("messages");
      const targetDoc = await messagesRef.doc(input.messageId!).get();
      const targetData = targetDoc.data();
      if (!targetDoc.exists || !targetData) {
        throw new HttpsError("not-found", "メッセージが見つかりません");
      }
      if (targetData.senderId === reporterId) {
        throw new HttpsError("invalid-argument", "自分のメッセージは通報できません");
      }
      if (typeof targetData.senderId !== "string" || targetData.senderId.startsWith("system:")) {
        throw new HttpsError("invalid-argument", "このメッセージは通報できません");
      }
      targetUserId = targetData.senderId;
      targetSeed = typeof targetData.senderRhingSeed === "string" ? targetData.senderRhingSeed : null;

      // 前後のメッセージ（送信日時順）。複合インデックスが要らない単一フィールドの並べ替え。
      const sentAt = targetData.sentAt;
      const [beforeSnap, afterSnap] = await Promise.all([
        sentAt
          ? messagesRef
              .orderBy("sentAt", "desc")
              .startAfter(sentAt)
              .limit(REPORT_CONTEXT_BEFORE)
              .get()
          : Promise.resolve(null),
        sentAt
          ? messagesRef
              .orderBy("sentAt", "asc")
              .startAfter(sentAt)
              .limit(REPORT_CONTEXT_AFTER)
              .get()
          : Promise.resolve(null),
      ]);
      const messages: EvidenceMessage[] = [
        ...(beforeSnap?.docs ?? [])
          .reverse()
          .map((d) => toEvidenceMessage(d.id, d.data(), false)),
        toEvidenceMessage(targetDoc.id, targetData, true),
        ...(afterSnap?.docs ?? []).map((d) => toEvidenceMessage(d.id, d.data(), false)),
      ];
      // 送信者のRhing Seedが無い古いメッセージは、住人の文書から補う。
      const missing = [
        ...new Set(messages.filter((m) => !m.senderRhingSeed && m.senderId).map((m) => m.senderId)),
      ].filter((id) => !id.startsWith("system:"));
      if (missing.length > 0) {
        const users = await db.getAll(...missing.map((id) => db.collection("users").doc(id)));
        const seeds = new Map(users.map((u) => [u.id, u.data()?.rhingSeed as string | undefined]));
        for (const m of messages) {
          if (!m.senderRhingSeed) m.senderRhingSeed = seeds.get(m.senderId) ?? null;
        }
      }
      evidence = {
        conversation: {
          kind: isDm ? "dm" : "group",
          conversationId: conversation.id,
          roomId: input.roomId,
          ...(isDm ? {} : { groupName: typeof c.name === "string" ? c.name : "" }),
        },
        messages,
      };
    }

    try {
      await reportRef.create({
        targetType: input.targetType,
        reason: input.reason,
        note: input.note,
        reporterId,
        reporterSeed,
        targetUserId,
        targetSeed,
        messageId: input.messageId ?? null,
        evidence,
        status: "open",
        createdAt: FieldValue.serverTimestamp(),
      });
    } catch (error) {
      // 同時に2回送られた場合は、先に作られた方を残す。
      if ((error as { code?: number }).code === 6) {
        return { alreadyReported: true };
      }
      throw error;
    }
    logger.info(`通報を受付: ${input.targetType} ${reportRef.id}`);
    return { alreadyReported: false };
  },
);

/** 通報の一覧（管理者のみ）。新しい順に最大200件。未対応・対応済みの絞り込みは画面側。 */
export const listReports = onCall(
  { region: "asia-northeast1" },
  async (request) => {
    assertAdmin(request);
    const snapshot = await db
      .collection("reports")
      .orderBy("createdAt", "desc")
      .limit(200)
      .get();
    const iso = (value: unknown): string | null =>
      value instanceof Timestamp ? value.toDate().toISOString() : null;
    return {
      reports: snapshot.docs.map((doc) => {
        const d = doc.data();
        return {
          reportId: doc.id,
          targetType: d.targetType ?? "",
          reason: d.reason ?? "",
          note: d.note ?? "",
          reporterId: d.reporterId ?? "",
          reporterSeed: d.reporterSeed ?? null,
          targetUserId: d.targetUserId ?? null,
          targetSeed: d.targetSeed ?? null,
          messageId: d.messageId ?? null,
          evidence: d.evidence ?? {},
          status: d.status ?? "open",
          createdAt: iso(d.createdAt),
          resolution: d.resolution ?? null,
          resolutionNote: d.resolutionNote ?? null,
          resolvedBy: d.resolvedBy ?? null,
          resolvedAt: iso(d.resolvedAt),
        };
      }),
    };
  },
);

/**
 * 通報を処理済みにする（管理者のみ）。`dismissed`＝問題なし、`actioned`＝対応済み
 * （停止などの対応は、既存の`suspendUserAccount`等で別に行う）。監査ログに残す。
 */
export const resolveReport = onCall(
  { region: "asia-northeast1" },
  async (request) => {
    assertAdmin(request);
    const reportId = request.data?.reportId;
    if (typeof reportId !== "string" || !reportId) {
      throw new HttpsError("invalid-argument", "reportIdが必要です");
    }
    const parsed = parseResolution(request.data);
    if (!parsed.ok) {
      throw new HttpsError("invalid-argument", parsed.reason);
    }
    const ref = db.collection("reports").doc(reportId);
    const doc = await ref.get();
    if (!doc.exists) {
      throw new HttpsError("not-found", "通報が見つかりません");
    }
    await ref.update({
      status: "resolved",
      resolution: parsed.value.resolution,
      resolutionNote: parsed.value.note,
      resolvedBy: request.auth!.uid,
      resolvedAt: FieldValue.serverTimestamp(),
    });
    const targetUserId = doc.data()?.targetUserId;
    await writeAdminAuditLog({
      adminUid: request.auth!.uid,
      action: "resolveReport",
      targetUserIds: typeof targetUserId === "string" ? [targetUserId] : [],
      reason: parsed.value.resolution,
      ...(parsed.value.note ? { note: parsed.value.note } : {}),
    });
  },
);
