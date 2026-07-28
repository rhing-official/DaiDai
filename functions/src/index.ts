import { initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import {
  FieldValue,
  getFirestore,
  Timestamp,
  type WriteBatch,
} from "firebase-admin/firestore";
import { logger } from "firebase-functions";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";

initializeApp();

const db = getFirestore();

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
 * 同じ操作）。長の場合は長交代の仕組みが無いため除去せず通知のみ行う。 */
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

