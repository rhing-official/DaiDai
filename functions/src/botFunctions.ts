import {
  FieldPath,
  FieldValue,
  Timestamp,
  getFirestore,
} from "firebase-admin/firestore";
import { HttpsError, onCall, onRequest } from "firebase-functions/v2/https";

import {
  BOT_MAX_PER_GROUP,
  BOT_MAX_PER_OWNER,
  BotGroupStatus,
  BotScope,
  Cursor,
  botSenderId,
  canAddBotsDirectly,
  canApproveBots,
  canConsentDmBot,
  encodeCursor,
  generateBotToken,
  hashBotToken,
  isReadableByBot,
  normalizeBotName,
  parseBotAuthorization,
  parseBotPostPayload,
  parseBotRoute,
  parseReadParams,
  previewOf,
  snippetOf,
  verifyBotToken,
} from "./botApi";
import { nextRateState } from "./webhook";

/**
 * bot API（段階2a、2026-11-09）のFirebase側。純粋なロジックは`botApi.ts`
 * （単体テスト済み）。設計は`文書/botAPI設計.md`。
 *
 * データ:
 * - `bots/{botId}`: 住人が持つbot（`ownerUserId`・`name`・`tokenHash`・
 *   `groupIds`＝追加を要求した/追加された広場）。クライアントは本人だけが
 *   読める。書き込みは常にこのファイルの関数（Admin SDK）経由。
 * - `groups/{groupId}/bots/{botId}`: 広場への追加（`status`＝pending/active、
 *   `addedAt`＝**この時刻以降のメッセージだけ**botが読める）。
 */

const REGION = "asia-northeast1";
const db = () => getFirestore();

function requireUid(request: { auth?: { uid?: string } }): string {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "ログインが必要です");
  return uid;
}

function str(value: unknown, label: string): string {
  if (typeof value !== "string" || value.length === 0) {
    throw new HttpsError("invalid-argument", `${label}が必要です`);
  }
  return value;
}

async function ownedBot(uid: string, botId: string) {
  const ref = db().doc(`bots/${botId}`);
  const snap = await ref.get();
  const bot = snap.data();
  if (!snap.exists || bot?.ownerUserId !== uid) {
    throw new HttpsError("not-found", "botが見つかりません");
  }
  return { ref, bot: bot! };
}

const COLLECTION: Record<BotScope, string> = {
  group: "groups",
  dm: "directMessages",
};
/** botのドキュメントが持つ、追加を要求した/追加された会話idの配列名。 */
const BOT_ARRAY: Record<BotScope, string> = { group: "groupIds", dm: "dmIds" };

interface Target {
  scope: BotScope;
  id: string;
}

/** callableの引数から対象の会話を決める（`groupId`か`dmId`のどちらか一方）。 */
function targetOf(data: Record<string, unknown> | undefined): Target {
  const groupId = data?.groupId;
  const dmId = data?.dmId;
  if (typeof groupId === "string" && groupId && dmId === undefined) {
    return { scope: "group", id: groupId };
  }
  if (typeof dmId === "string" && dmId && groupId === undefined) {
    return { scope: "dm", id: dmId };
  }
  throw new HttpsError("invalid-argument", "groupIdかdmIdのどちらかが必要です");
}

function convRef(target: Target) {
  return db().doc(`${COLLECTION[target.scope]}/${target.id}`);
}

function membersOf(scope: BotScope, data: FirebaseFirestore.DocumentData) {
  const key = scope === "group" ? "memberIds" : "participants";
  return (data[key] as string[] | undefined) ?? [];
}

/** [uid]が会話の参加者（広場のメンバー・一対の参加者）であることを確かめる。 */
async function memberConversation(uid: string, target: Target) {
  const ref = convRef(target);
  const snap = await ref.get();
  const data = snap.data();
  if (!snap.exists || !data || !membersOf(target.scope, data).includes(uid)) {
    throw new HttpsError("permission-denied", "権限がありません");
  }
  return { ref, data };
}

/** 監査ログ（`botAuditLogs`、Admin SDKのみ書き込み。クライアントは読み書き不可）。 */
async function audit(
  action: string,
  fields: {
    botId: string;
    actorId: string;
    groupId?: string;
    dmId?: string;
  },
): Promise<void> {
  await db()
    .collection("botAuditLogs")
    .add({ action, ...fields, at: FieldValue.serverTimestamp() });
}

function auditTarget(target: Target): { groupId?: string; dmId?: string } {
  return target.scope === "group" ? { groupId: target.id } : { dmId: target.id };
}

/** 追加・削除のお知らせの`contentType`（クライアントが言語に合わせて文にする）。 */
export const BOT_NOTICE_ADDED = "botAdded";
export const BOT_NOTICE_REMOVED = "botRemoved";

/**
 * botが読める全ての寄合に、追加・削除のお知らせ（システムメッセージ）を残す。
 * 通知・未読・語らい一覧の最終メッセージには影響させない。
 */
async function postBotNotice(
  target: Target,
  botName: string,
  kind: typeof BOT_NOTICE_ADDED | typeof BOT_NOTICE_REMOVED,
): Promise<void> {
  const ref = convRef(target);
  const conv = (await ref.get()).data();
  if (!conv) return;
  const rooms = await ref.collection("rooms").get();
  const batch = db().batch();
  for (const room of rooms.docs) {
    if (!isOpenRoom(target.scope, conv, room.data())) continue;
    batch.set(room.ref.collection("messages").doc(), {
      conversationId: room.id,
      conversationType: target.scope === "group" ? "room" : "dm",
      senderId: "system:bot",
      senderRhingSeed: null,
      botName: "DaiDai",
      content: botName,
      contentType: kind,
      sentAt: FieldValue.serverTimestamp(),
      hiddenFor: [],
      readBy: [],
      isSpam: false,
      silent: true,
      replyToMessageId: null,
      replyToSenderId: null,
      replyToSenderRhingSeed: null,
      replyToSnippet: null,
      editedAt: null,
      reactions: {},
    });
  }
  await batch.commit();
}

/** botを作る。トークンは**この応答でしか返さない**。 */
export const createBot = onCall({ region: REGION }, async (request) => {
  const uid = requireUid(request);
  const name = normalizeBotName(request.data?.name);
  if (name === null) {
    throw new HttpsError("invalid-argument", "名前が正しくありません");
  }
  const owned = await db()
    .collection("bots")
    .where("ownerUserId", "==", uid)
    .count()
    .get();
  if (owned.data().count >= BOT_MAX_PER_OWNER) {
    throw new HttpsError(
      "failed-precondition",
      `botは1人${BOT_MAX_PER_OWNER}個までです`,
    );
  }
  const ref = db().collection("bots").doc();
  const token = generateBotToken(ref.id);
  await ref.set({
    ownerUserId: uid,
    name,
    createdAt: FieldValue.serverTimestamp(),
    tokenHash: hashBotToken(token),
    groupIds: [],
    lastUsedAt: null,
    rateWindowStartMs: null,
    rateCount: 0,
  });
  await audit("createBot", { botId: ref.id, actorId: uid });
  return { botId: ref.id, token };
});

/** トークンを作り直す（古いトークンは即座に無効）。 */
export const rotateBotToken = onCall({ region: REGION }, async (request) => {
  const uid = requireUid(request);
  const botId = str(request.data?.botId, "botId");
  const { ref } = await ownedBot(uid, botId);
  const token = generateBotToken(botId);
  await ref.update({ tokenHash: hashBotToken(token) });
  await audit("rotateBotToken", { botId, actorId: uid });
  return { token };
});

/** botを削除する（追加されている広場・一対からも外れる）。 */
export const deleteBot = onCall({ region: REGION }, async (request) => {
  const uid = requireUid(request);
  const botId = str(request.data?.botId, "botId");
  const { ref, bot } = await ownedBot(uid, botId);
  const activeTargets: Target[] = [];
  const batch = db().batch();
  for (const scope of ["group", "dm"] as const) {
    for (const id of (bot[BOT_ARRAY[scope]] as string[] | undefined) ?? []) {
      const memberRef = db().doc(`${COLLECTION[scope]}/${id}/bots/${botId}`);
      if ((await memberRef.get()).data()?.status === "active") {
        activeTargets.push({ scope, id });
      }
      batch.delete(memberRef);
    }
  }
  batch.delete(ref);
  await batch.commit();
  for (const target of activeTargets) {
    await postBotNotice(target, bot.name as string, BOT_NOTICE_REMOVED);
  }
  await audit("deleteBot", { botId, actorId: uid });
  return { ok: true };
});

/**
 * 自分のbotを広場（`groupId`）または一対（`dmId`）へ追加する。
 * - 広場: 長・`manageBots`・`addBots`を持つ人が追加すれば即`active`、そうでなければ
 *   `pending`（`manageBots`を持つメンバーの承認待ち）。
 * - 一対: **常に`pending`**（もう一方の参加者の同意が前提）。
 * 再追加のたびに`addedAt`が新しくなり、外していた間の履歴は読めない。
 */
export const requestBotAddition = onCall(
  { region: REGION },
  async (request) => {
    const uid = requireUid(request);
    const botId = str(request.data?.botId, "botId");
    const target = targetOf(request.data);
    const { ref: botRef, bot } = await ownedBot(uid, botId);
    const { ref, data } = await memberConversation(uid, target);

    const memberRef = ref.collection("bots").doc(botId);
    if ((await memberRef.get()).exists) {
      throw new HttpsError("already-exists", "既に追加されています");
    }
    const count = await ref.collection("bots").count().get();
    if (count.data().count >= BOT_MAX_PER_GROUP) {
      throw new HttpsError(
        "failed-precondition",
        `botは1つの会話に${BOT_MAX_PER_GROUP}個までです`,
      );
    }
    const status: BotGroupStatus =
      target.scope === "group" && canAddBotsDirectly(data, uid)
        ? "active"
        : "pending";
    const batch = db().batch();
    batch.set(memberRef, {
      botId,
      name: bot.name as string,
      ownerUserId: uid,
      addedBy: uid,
      status,
      requestedAt: FieldValue.serverTimestamp(),
      addedAt: status === "active" ? FieldValue.serverTimestamp() : null,
    });
    batch.update(botRef, {
      [BOT_ARRAY[target.scope]]: FieldValue.arrayUnion(target.id),
    });
    await batch.commit();
    if (status === "active") {
      await postBotNotice(target, bot.name as string, BOT_NOTICE_ADDED);
    }
    await audit(status === "active" ? "addBot" : "requestBot", {
      botId,
      actorId: uid,
      ...auditTarget(target),
    });
    return { status };
  },
);

/**
 * 承認待ちのbotを承認（`active`に）または却下（削除）する。広場は長・
 * `manageBots`権限者、一対は**botの所有者以外の参加者**（同意）。
 */
export const respondBotAddition = onCall(
  { region: REGION },
  async (request) => {
    const uid = requireUid(request);
    const botId = str(request.data?.botId, "botId");
    const approve = request.data?.approve === true;
    const target = targetOf(request.data);
    const { ref, data } = await memberConversation(uid, target);
    const memberRef = ref.collection("bots").doc(botId);
    const snap = await memberRef.get();
    if (!snap.exists || snap.data()?.status !== "pending") {
      throw new HttpsError("not-found", "承認待ちのbotがありません");
    }
    const allowed =
      target.scope === "group"
        ? canApproveBots(data, uid)
        : canConsentDmBot(data, uid, snap.data()?.ownerUserId as string);
    if (!allowed) {
      throw new HttpsError("permission-denied", "権限がありません");
    }
    if (approve) {
      await memberRef.update({
        status: "active",
        addedAt: FieldValue.serverTimestamp(),
        approvedBy: uid,
      });
      await postBotNotice(target, snap.data()?.name as string, BOT_NOTICE_ADDED);
      await audit("approveBot", { botId, actorId: uid, ...auditTarget(target) });
    } else {
      const batch = db().batch();
      batch.delete(memberRef);
      batch.update(db().doc(`bots/${botId}`), {
        [BOT_ARRAY[target.scope]]: FieldValue.arrayRemove(target.id),
      });
      await batch.commit();
      await audit("rejectBot", { botId, actorId: uid, ...auditTarget(target) });
    }
    return { ok: true };
  },
);

/**
 * botを会話から外す。広場はbotの所有者または`manageBots`権限者、一対は
 * どちらの参加者でも外せる。
 */
export const removeBotFromGroup = onCall(
  { region: REGION },
  async (request) => {
    const uid = requireUid(request);
    const botId = str(request.data?.botId, "botId");
    const target = targetOf(request.data);
    const { ref, data } = await memberConversation(uid, target);
    const memberRef = ref.collection("bots").doc(botId);
    const snap = await memberRef.get();
    if (!snap.exists) {
      throw new HttpsError("not-found", "botが見つかりません");
    }
    const allowed =
      target.scope === "dm" ||
      snap.data()?.ownerUserId === uid ||
      canApproveBots(data, uid);
    if (!allowed) {
      throw new HttpsError("permission-denied", "権限がありません");
    }
    const batch = db().batch();
    batch.delete(memberRef);
    batch.update(db().doc(`bots/${botId}`), {
      [BOT_ARRAY[target.scope]]: FieldValue.arrayRemove(target.id),
    });
    await batch.commit();
    if (snap.data()?.status === "active") {
      await postBotNotice(target, snap.data()?.name as string, BOT_NOTICE_REMOVED);
    }
    await audit("removeBot", { botId, actorId: uid, ...auditTarget(target) });
    return { ok: true };
  },
);

// ---------------------------------------------------------------------------
// HTTP API（`Authorization: Bot <token>`）
// ---------------------------------------------------------------------------

type Json = Record<string, unknown>;

/** 広場でactiveなbotの追加情報（`addedAt`以降だけ読める）。 */
async function activeMembership(
  target: Target,
  botId: string,
): Promise<{ addedAt: Timestamp } | null> {
  const snap = await db()
    .doc(`${COLLECTION[target.scope]}/${target.id}/bots/${botId}`)
    .get();
  const data = snap.data();
  if (!data || data.status !== "active" || !(data.addedAt instanceof Timestamp)) {
    return null;
  }
  return { addedAt: data.addedAt };
}

/**
 * botが読み書きできる寄合か。広場の**全員が入っている寄合**だけ（一部の
 * メンバーだけの寄合は、bot追加の同意が及ばない為、対象外にする）。
 */
function isOpenRoom(
  scope: BotScope,
  conv: FirebaseFirestore.DocumentData,
  room: FirebaseFirestore.DocumentData,
): boolean {
  const key = scope === "group" ? "memberIds" : "participants";
  const convMembers = (conv[key] as string[] | undefined) ?? [];
  const roomMembers = new Set((room[key] as string[] | undefined) ?? []);
  return convMembers.every((id) => roomMembers.has(id));
}

function messageJson(
  id: string,
  data: FirebaseFirestore.DocumentData,
): Json {
  const sentAt = data.sentAt as Timestamp | undefined;
  const isText = data.contentType === "text";
  return {
    id,
    senderId: data.senderId ?? null,
    senderName: (data.botName as string | null) ?? data.senderRhingSeed ?? null,
    isBot: typeof data.botName === "string",
    contentType: data.contentType ?? "text",
    // 文字以外（画像・ファイル等）は本文を返さない（段階2aは文字のみ）。
    content: isText ? (data.content ?? "") : "",
    sentAt: sentAt?.toDate().toISOString() ?? null,
    replyToMessageId: data.replyToMessageId ?? null,
    editedAt: (data.editedAt as Timestamp | null)?.toDate().toISOString() ?? null,
  };
}

/** [query]に結果が出るまで最大[timeoutMs]待つ（ロングポーリング）。 */
function waitForResults(
  query: FirebaseFirestore.Query,
  timeoutMs: number,
): Promise<FirebaseFirestore.QuerySnapshot | null> {
  return new Promise((resolve) => {
    let finished = false;
    let unsubscribe: (() => void) | null = null;
    const finish = (snap: FirebaseFirestore.QuerySnapshot | null) => {
      if (finished) return;
      finished = true;
      clearTimeout(timer);
      unsubscribe?.();
      resolve(snap);
    };
    const timer = setTimeout(() => finish(null), timeoutMs);
    unsubscribe = query.onSnapshot(
      (snap) => {
        if (!snap.empty) finish(snap);
      },
      () => finish(null),
    );
  });
}

/** 広場の最終メッセージの控えを、残っている最新のメッセージから作り直す。 */
async function refreshLastMessage(
  groupRef: FirebaseFirestore.DocumentReference,
): Promise<void> {
  const rooms = await groupRef.collection("rooms").get();
  let best: FirebaseFirestore.DocumentData | null = null;
  for (const room of rooms.docs) {
    const latest = await room.ref
      .collection("messages")
      .orderBy("sentAt", "desc")
      .limit(10)
      .get();
    for (const doc of latest.docs) {
      const data = doc.data();
      if (data.contentType === BOT_NOTICE_ADDED || data.contentType === BOT_NOTICE_REMOVED) {
        continue;
      }
      const at = data.sentAt as Timestamp | undefined;
      if (!at) continue;
      if (!best || at.toMillis() > (best.sentAt as Timestamp).toMillis()) {
        best = data;
      }
      break;
    }
  }
  if (!best) {
    await groupRef.update({
      lastMessageAt: FieldValue.delete(),
      lastMessageSenderId: FieldValue.delete(),
      lastMessageContentType: FieldValue.delete(),
      lastMessagePreview: FieldValue.delete(),
    });
    return;
  }
  const hasPreview = best.contentType === "text" || best.contentType === "call";
  await groupRef.update({
    lastMessageAt: best.sentAt,
    lastMessageSenderId: best.senderId,
    lastMessageContentType: best.contentType,
    lastMessagePreview:
      hasPreview && typeof best.content === "string"
        ? previewOf(best.content)
        : null,
  });
}

export const botApi = onRequest(
  { region: REGION, timeoutSeconds: 60, invoker: "public" },
  async (req, res) => {
    res.set("Cache-Control", "no-store");
    const route = parseBotRoute(req.method, req.path);
    if (!route) {
      res.status(404).json({ error: "not_found" });
      return;
    }
    const auth = parseBotAuthorization(req.headers.authorization);
    const botRef = auth ? db().doc(`bots/${auth.botId}`) : null;
    const bot = botRef ? (await botRef.get()).data() : undefined;
    if (!auth || !botRef || !bot || !verifyBotToken(auth.token, bot.tokenHash)) {
      res.status(401).json({ error: "unauthorized" });
      return;
    }
    const botId = auth.botId;

    // レート制限（1botあたり固定窓、全リクエスト共通）。
    const allowed = await db().runTransaction(async (tx) => {
      const fresh = (await tx.get(botRef)).data();
      if (!fresh) return false;
      const decision = nextRateState(
        {
          windowStartMs: (fresh.rateWindowStartMs as number | null) ?? null,
          count: (fresh.rateCount as number | undefined) ?? 0,
        },
        Date.now(),
      );
      if (decision.allowed) {
        tx.update(botRef, {
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

    if (route.kind === "me") {
      res.json({ id: botId, name: bot.name });
      return;
    }

    if (route.kind === "conversations") {
      const conversations: Json[] = [];
      for (const scope of ["group", "dm"] as const) {
        for (const id of (bot[BOT_ARRAY[scope]] as string[] | undefined) ?? []) {
          const target: Target = { scope, id };
          const membership = await activeMembership(target, botId);
          if (!membership) continue;
          const conv = (await convRef(target).get()).data();
          if (!conv) continue;
          const rooms = await convRef(target).collection("rooms").get();
          conversations.push({
            type: scope === "group" ? "group" : "dm",
            [scope === "group" ? "groupId" : "dmId"]: id,
            name: scope === "group" ? (conv.name ?? null) : null,
            addedAt: membership.addedAt.toDate().toISOString(),
            rooms: rooms.docs
              .filter((r) => isOpenRoom(scope, conv, r.data()))
              .map((r) => ({ roomId: r.id, name: r.data().name ?? null })),
          });
        }
      }
      res.json({ conversations });
      return;
    }

    // ここから先は広場・一対の寄合に対する操作。
    const { scope, conversationId, roomId } = route;
    const target: Target = { scope, id: conversationId };
    const membership = await activeMembership(target, botId);
    const convDocRef = convRef(target);
    const roomRef = convDocRef.collection("rooms").doc(roomId);
    const [convSnap, roomSnap] = await Promise.all([
      convDocRef.get(),
      roomRef.get(),
    ]);
    const group = convSnap.data();
    const room = roomSnap.data();
    if (!membership || !group || !room || !isOpenRoom(scope, group, room)) {
      // 追加されていない・存在しない・対象外の寄合は区別せず403。
      res.status(403).json({ error: "forbidden" });
      return;
    }
    const messages = roomRef.collection("messages");

    if (route.kind === "readMessages") {
      const params = parseReadParams(req.query);
      if (!params) {
        res.status(400).json({ error: "invalid_query" });
        return;
      }
      let query: FirebaseFirestore.Query = messages
        .where("sentAt", ">=", membership.addedAt)
        .orderBy("sentAt")
        .orderBy(FieldPath.documentId());
      if (params.cursor) {
        query = query.startAfter(
          new Timestamp(params.cursor.seconds, params.cursor.nanos),
          params.cursor.messageId,
        );
      }
      query = query.limit(params.limit);

      let snap: FirebaseFirestore.QuerySnapshot | null = await query.get();
      if (snap.empty && params.waitSeconds > 0) {
        snap = await waitForResults(query, params.waitSeconds * 1000);
      }
      const docs = snap?.docs ?? [];
      const readable = docs.filter((d) => isReadableByBot(d.data()));
      // 見せないメッセージ（他のbot等）を読み飛ばした分もカーソルは進める。
      let nextCursor: string | null = params.cursor
        ? encodeCursor(params.cursor)
        : null;
      const last = docs[docs.length - 1];
      if (last) {
        const sentAt = last.data().sentAt as Timestamp;
        const cursor: Cursor = {
          seconds: sentAt.seconds,
          nanos: sentAt.nanoseconds,
          messageId: last.id,
        };
        nextCursor = encodeCursor(cursor);
      }
      res.json({
        messages: readable.map((d) => messageJson(d.id, d.data())),
        nextCursor,
      });
      return;
    }

    if (route.kind === "deleteMessage") {
      // 取り消せるのは、そのbot自身の投稿だけ。
      const messageDoc = messages.doc(route.messageId);
      const targetData = (await messageDoc.get()).data();
      if (!targetData || targetData.senderId !== botSenderId(botId)) {
        res.status(404).json({ error: "not_found" });
        return;
      }
      const targetSentAt = targetData.sentAt as Timestamp | undefined;
      await messageDoc.delete();
      // 取り消したのが語らい一覧の最終メッセージなら、残った最新のものへ直す。
      if (
        targetSentAt &&
        (group.lastMessageAt as Timestamp | undefined)?.isEqual(targetSentAt) &&
        group.lastMessageSenderId === botSenderId(botId)
      ) {
        await refreshLastMessage(convDocRef);
      }
      await audit("deleteBotMessage", {
        botId,
        actorId: `bot:${botId}`,
        ...auditTarget(target),
      });
      res.status(200).json({ ok: true });
      return;
    }

    // postMessage
    const contentLength = Number(req.headers["content-length"] ?? 0);
    if (contentLength > 10 * 1024) {
      res.status(413).json({ error: "payload_too_large" });
      return;
    }
    if (!req.is("application/json")) {
      res.status(415).json({ error: "unsupported_media_type" });
      return;
    }
    const payload = parseBotPostPayload(req.body);
    if (!payload.ok) {
      res.status(400).json({ error: "invalid_payload", message: payload.reason });
      return;
    }

    let reply: Json = {
      replyToMessageId: null,
      replyToSenderId: null,
      replyToSenderRhingSeed: null,
      replyToSnippet: null,
    };
    if (payload.replyToMessageId) {
      const target = (await messages.doc(payload.replyToMessageId).get()).data();
      // 引用できるのは、botが読める（追加後の）メッセージだけ。
      const targetSentAt = target?.sentAt as Timestamp | undefined;
      if (
        !target ||
        !targetSentAt ||
        targetSentAt.toMillis() < membership.addedAt.toMillis()
      ) {
        res.status(400).json({
          error: "invalid_payload",
          message: "replyToMessageIdのメッセージが見つかりません",
        });
        return;
      }
      reply = {
        replyToMessageId: payload.replyToMessageId,
        replyToSenderId: target.senderId ?? null,
        replyToSenderRhingSeed:
          (target.botName as string | null) ?? target.senderRhingSeed ?? null,
        replyToSnippet:
          target.contentType === "text" && typeof target.content === "string"
            ? snippetOf(target.content)
            : null,
      };
    }

    const messageRef = messages.doc();
    const sender = botSenderId(botId);
    const batch = db().batch();
    batch.set(messageRef, {
      conversationId: roomId,
      conversationType: scope === "group" ? "room" : "dm",
      senderId: sender,
      senderRhingSeed: null,
      botName: bot.name as string,
      content: payload.content,
      contentType: "text",
      sentAt: FieldValue.serverTimestamp(),
      hiddenFor: [],
      readBy: [],
      isSpam: false,
      silent: payload.silent,
      ...reply,
      editedAt: null,
      reactions: {},
    });
    batch.update(roomRef, { lastMessageAt: FieldValue.serverTimestamp() });
    batch.update(convDocRef, {
      lastMessageAt: FieldValue.serverTimestamp(),
      lastMessageSenderId: sender,
      lastMessageContentType: "text",
      lastMessagePreview: previewOf(payload.content),
    });
    await batch.commit();
    res.status(200).json({ ok: true, messageId: messageRef.id });
  },
);
