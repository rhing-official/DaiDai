import {
  FieldPath,
  FieldValue,
  Timestamp,
  getFirestore,
} from "firebase-admin/firestore";
import { HttpsError, onCall, onRequest } from "firebase-functions/v2/https";

import {
  ASSISTANT_KIND,
  BOT_CONTENT_MAX_LENGTH,
  BOT_MAX_PER_OWNER,
  BotScope,
  Cursor,
  assistantHistoryFloor,
  botSenderId,
  encodeCursor,
  ensureMentionText,
  generateBotToken,
  hashBotToken,
  isReadableByAssistant,
  normalizeBotName,
  parseBotAuthorization,
  parseBotPostPayload,
  parseBotRoute,
  parseReadParams,
  parseUpdatesParams,
  previewOf,
  snippetOf,
  verifyBotToken,
} from "./botApi";
import { nextRateState } from "./webhook";

/**
 * AIエージェント連携（bot API）のFirebase側。純粋なロジックは`botApi.ts`（単体テスト済み）。
 * 設計は`文書/botAPI設計.md`。
 *
 * 2026-11-09に、会話ごとにBOTを追加・承認・同意する方式をやめ、**所有者が参加している
 * 全ての広場・一対を扱うAIエージェント連携**へ一本化した（ユーザー決定）。トークンの
 * 持ち主＝所有者の閲覧範囲が、そのままAIの読める範囲になる。
 *
 * データ: `bots/{botId}`（`ownerUserId`・`name`・`tokenHash`）。クライアントは所有者
 * だけが読める。書き込みは常にこのファイルの関数（Admin SDK）経由。
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
    throw new HttpsError("not-found", "AIエージェント連携が見つかりません");
  }
  return { ref, bot: bot! };
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

/** AIエージェント連携のトークンを作る。トークンは**この応答でしか返さない**。 */
export const createBot = onCall({ region: REGION, invoker: "public" }, async (request) => {
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
      `AIエージェント連携は1人${BOT_MAX_PER_OWNER}個までです`,
    );
  }
  const ref = db().collection("bots").doc();
  const token = generateBotToken(ref.id);
  await ref.set({
    ownerUserId: uid,
    kind: ASSISTANT_KIND,
    name,
    createdAt: FieldValue.serverTimestamp(),
    tokenHash: hashBotToken(token),
    lastUsedAt: null,
    rateWindowStartMs: null,
    rateCount: 0,
  });
  await audit("createAssistant", { botId: ref.id, actorId: uid });
  return { botId: ref.id, token };
});

/** トークンを作り直す（古いトークンは即座に無効）。 */
export const rotateBotToken = onCall({ region: REGION, invoker: "public" }, async (request) => {
  const uid = requireUid(request);
  const botId = str(request.data?.botId, "botId");
  const { ref } = await ownedBot(uid, botId);
  const token = generateBotToken(botId);
  await ref.update({ tokenHash: hashBotToken(token) });
  await audit("rotateBotToken", { botId, actorId: uid });
  return { token };
});

/** AIエージェント連携を削除する（トークンは即座に無効）。 */
export const deleteBot = onCall({ region: REGION, invoker: "public" }, async (request) => {
  const uid = requireUid(request);
  const botId = str(request.data?.botId, "botId");
  const { ref } = await ownedBot(uid, botId);
  await ref.delete();
  await audit("deleteBot", { botId, actorId: uid });
  return { ok: true };
});

// ---------------------------------------------------------------------------
// HTTP API（`Authorization: Bot <token>`）
// ---------------------------------------------------------------------------

type Json = Record<string, unknown>;

interface Target {
  scope: BotScope;
  id: string;
}

const COLLECTION: Record<BotScope, string> = {
  group: "groups",
  dm: "directMessages",
};

function convRef(target: Target) {
  return db().doc(`${COLLECTION[target.scope]}/${target.id}`);
}

function membersOf(scope: BotScope, data: FirebaseFirestore.DocumentData) {
  const key = scope === "group" ? "memberIds" : "participants";
  return (data[key] as string[] | undefined) ?? [];
}

async function isBlocked(ownerId: string, otherId: string | undefined) {
  if (!otherId) return false;
  return (await db().doc(`users/${ownerId}/blockedUsers/${otherId}`).get())
    .exists;
}

/** [ownerId]が参加している広場・一対（ブロックしている相手との一対は除く）。 */
async function ownerConversations(
  ownerId: string,
): Promise<{ target: Target; data: FirebaseFirestore.DocumentData }[]> {
  const [groups, dms] = await Promise.all([
    db().collection("groups").where("memberIds", "array-contains", ownerId).get(),
    db()
      .collection("directMessages")
      .where("participants", "array-contains", ownerId)
      .get(),
  ]);
  const result: { target: Target; data: FirebaseFirestore.DocumentData }[] = [];
  for (const g of groups.docs) {
    result.push({ target: { scope: "group", id: g.id }, data: g.data() });
  }
  for (const d of dms.docs) {
    const other = membersOf("dm", d.data()).find((id) => id !== ownerId);
    if (await isBlocked(ownerId, other)) continue;
    result.push({ target: { scope: "dm", id: d.id }, data: d.data() });
  }
  return result;
}

/**
 * 相手（[otherId]）がこの一対（[conversationId]）に対して表示している呼び名。
 * `lib/models/app_user.dart`の`AppUser.effectiveNicknameFor`と同じロジック
 * （この会話専用のプロフィールカード→標準の適用中カード→個別の
 * activeNicknameId、の順）をサーバー側で再現する。見つからなければnull。
 */
async function effectiveNicknameFor(
  otherId: string,
  conversationId: string,
): Promise<string | null> {
  const user = (await db().doc(`users/${otherId}`).get()).data();
  if (!user) return null;
  const profileCards =
    (user.profileCards as { id: string; nicknameId?: string }[] | undefined) ??
    [];
  const nicknames =
    (user.nicknames as { id: string; text: string }[] | undefined) ?? [];
  const overrideId = (
    user.conversationProfileCardId as Record<string, string> | undefined
  )?.[conversationId];
  const card =
    (overrideId ? profileCards.find((c) => c.id === overrideId) : undefined) ??
    profileCards.find((c) => c.id === (user.activeProfileCardId as string | undefined));
  const nicknameId = card
    ? card.nicknameId
    : (user.activeNicknameId as string | undefined);
  if (!nicknameId) return null;
  return nicknames.find((n) => n.id === nicknameId)?.text ?? null;
}

/**
 * その会話での[userId]の呼び名（メンション・参加者一覧用）。その語らいで使っている
 * 呼び名があればそれ、無ければRhing Seed（`@`は付けない。本文には`@$label`で入る）。
 * 見つからなければnull。
 */
async function memberLabel(
  userId: string,
  conversationId: string,
): Promise<string | null> {
  const nickname = await effectiveNicknameFor(userId, conversationId);
  if (nickname) return nickname;
  const user = (await db().doc(`users/${userId}`).get()).data();
  return (user?.rhingSeed as string | undefined) ?? null;
}

/** 会話の表示名（広場は広場名、一対は相手の呼び名。無ければRhing Seed）。 */
async function conversationName(
  scope: BotScope,
  data: FirebaseFirestore.DocumentData,
  ownerId: string,
  conversationId: string,
): Promise<string | null> {
  if (scope === "group") return (data.name as string | undefined) ?? null;
  const other = membersOf("dm", data).find((id) => id !== ownerId);
  if (!other) return null;
  const nickname = await effectiveNicknameFor(other, conversationId);
  if (nickname) return nickname;
  const seed = (data.participantRhingSeeds as Record<string, string> | undefined)?.[
    other
  ];
  return seed ? `@${seed}` : null;
}

function messageJson(
  id: string,
  data: FirebaseFirestore.DocumentData,
  ownSenderId: string,
): Json {
  const sentAt = data.sentAt as Timestamp | undefined;
  const isText = data.contentType === "text";
  return {
    id,
    senderId: data.senderId ?? null,
    senderName: (data.botName as string | null) ?? data.senderRhingSeed ?? null,
    isBot: typeof data.botName === "string",
    isSelf: data.senderId === ownSenderId,
    contentType: data.contentType ?? "text",
    // 文字以外（画像・ファイル等）は本文を返さない（現状は文字のみ）。
    content: isText ? (data.content ?? "") : "",
    sentAt: sentAt?.toDate().toISOString() ?? null,
    replyToMessageId: data.replyToMessageId ?? null,
    mentionedUserIds: Array.isArray(data.mentionedUserIds)
      ? data.mentionedUserIds
      : [],
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

/**
 * 更新のあった会話（`lastMessageAt`が[sinceMs]より新しい）を返す。無ければ
 * [waitMs]まで待つ（Firestoreの購読で、会話の本体への書き込みだけを見る）。
 */
async function waitForUpdates(
  ownerId: string,
  sinceMs: number,
  waitMs: number,
): Promise<{ target: Target; data: FirebaseFirestore.DocumentData }[]> {
  const collect = async () =>
    (await ownerConversations(ownerId)).filter(({ data }) => {
      const at = data.lastMessageAt as Timestamp | undefined;
      return at !== undefined && at.toMillis() > sinceMs;
    });
  const now = await collect();
  if (now.length > 0 || waitMs <= 0) return now;
  await new Promise<void>((resolve) => {
    let done = false;
    const unsubs: (() => void)[] = [];
    const finish = () => {
      if (done) return;
      done = true;
      clearTimeout(timer);
      unsubs.forEach((u) => u());
      resolve();
    };
    const timer = setTimeout(finish, waitMs);
    const watch = (q: FirebaseFirestore.Query) =>
      q.onSnapshot(
        (snap) => {
          for (const change of snap.docChanges()) {
            const at = change.doc.data().lastMessageAt as Timestamp | undefined;
            if (change.type !== "removed" && at && at.toMillis() > sinceMs) {
              finish();
            }
          }
        },
        () => finish(),
      );
    unsubs.push(
      watch(db().collection("groups").where("memberIds", "array-contains", ownerId)),
      watch(
        db()
          .collection("directMessages")
          .where("participants", "array-contains", ownerId),
      ),
    );
  });
  return collect();
}

/** 会話の最終メッセージの控えを、残っている最新のメッセージから作り直す。 */
async function refreshLastMessage(
  convDocRef: FirebaseFirestore.DocumentReference,
): Promise<void> {
  const rooms = await convDocRef.collection("rooms").get();
  let best: FirebaseFirestore.DocumentData | null = null;
  for (const room of rooms.docs) {
    const latest = await room.ref
      .collection("messages")
      .orderBy("sentAt", "desc")
      .limit(10)
      .get();
    for (const doc of latest.docs) {
      const data = doc.data();
      // 過去のbot追加・削除のお知らせ（現在は作らない）は最終メッセージにしない。
      if (data.contentType === "botAdded" || data.contentType === "botRemoved") {
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
    await convDocRef.update({
      lastMessageAt: FieldValue.delete(),
      lastMessageSenderId: FieldValue.delete(),
      lastMessageContentType: FieldValue.delete(),
      lastMessagePreview: FieldValue.delete(),
    });
    return;
  }
  const hasPreview = best.contentType === "text" || best.contentType === "call";
  await convDocRef.update({
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
    const ownerId = bot.ownerUserId as string;
    const ownSenderId = botSenderId(botId);

    // レート制限（1トークンあたり固定窓、全リクエスト共通）。
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

    if (route.kind === "updates") {
      const params = parseUpdatesParams(req.query);
      if (!params) {
        res.status(400).json({ error: "invalid_query" });
        return;
      }
      const updated = await waitForUpdates(
        ownerId,
        params.sinceMs,
        params.waitSeconds * 1000,
      );
      let nextSince = params.sinceMs;
      const conversations: Json[] = [];
      for (const { target, data } of updated) {
        const at = (data.lastMessageAt as Timestamp).toMillis();
        nextSince = Math.max(nextSince, at);
        conversations.push({
          type: target.scope,
          [target.scope === "group" ? "groupId" : "dmId"]: target.id,
          name: await conversationName(target.scope, data, ownerId, target.id),
          lastMessageAt: new Date(at).toISOString(),
          lastMessageSenderId: data.lastMessageSenderId ?? null,
          lastMessagePreview: data.lastMessagePreview ?? null,
        });
      }
      res.json({ conversations, nextSince: String(nextSince) });
      return;
    }

    if (route.kind === "conversations") {
      const conversations: Json[] = [];
      for (const { target, data } of await ownerConversations(ownerId)) {
        const rooms = await convRef(target).collection("rooms").get();
        conversations.push({
          type: target.scope,
          [target.scope === "group" ? "groupId" : "dmId"]: target.id,
          name: await conversationName(target.scope, data, ownerId, target.id),
          lastMessageAt:
            (data.lastMessageAt as Timestamp | undefined)
              ?.toDate()
              .toISOString() ?? null,
          rooms: rooms.docs
            .filter((r) => membersOf(target.scope, r.data()).includes(ownerId))
            .map((r) => ({ roomId: r.id, name: r.data().name ?? null })),
        });
      }
      res.json({ conversations });
      return;
    }

    // 参加者の一覧（メンション先を選ぶため）。所有者が参加している会話だけ。
    if (route.kind === "members") {
      const target: Target = { scope: route.scope, id: route.conversationId };
      const conv = (await convRef(target).get()).data();
      if (!conv || !membersOf(route.scope, conv).includes(ownerId)) {
        res.status(403).json({ error: "forbidden" });
        return;
      }
      const members: Json[] = [];
      for (const userId of membersOf(route.scope, conv)) {
        if (userId === ownerId) continue;
        // 所有者がブロックしている相手は、メンション先に出さない。
        if (await isBlocked(ownerId, userId)) continue;
        const name = await memberLabel(userId, route.conversationId);
        if (name) members.push({ userId, name });
      }
      res.json({ members });
      return;
    }

    // ここから先は広場・一対の寄合に対する操作。所有者が参加している寄合だけ。
    const { scope, conversationId, roomId } = route;
    const target: Target = { scope, id: conversationId };
    const convDocRef = convRef(target);
    const roomRef = convDocRef.collection("rooms").doc(roomId);
    const [convSnap, roomSnap] = await Promise.all([
      convDocRef.get(),
      roomRef.get(),
    ]);
    const conv = convSnap.data();
    const room = roomSnap.data();
    const partner =
      scope === "dm" && conv
        ? membersOf("dm", conv).find((id) => id !== ownerId)
        : undefined;
    if (
      !conv ||
      !room ||
      !membersOf(scope, conv).includes(ownerId) ||
      !membersOf(scope, room).includes(ownerId) ||
      (await isBlocked(ownerId, partner))
    ) {
      // 参加していない・存在しない・ブロック中は区別せず403。
      res.status(403).json({ error: "forbidden" });
      return;
    }
    // 読める下限時刻＝所有者本人が画面で見られる範囲（無制限ならnull）。
    const floor =
      scope === "group"
        ? ((assistantHistoryFloor(conv, room, ownerId) as Timestamp | null) ??
          null)
        : null;
    const messages = roomRef.collection("messages");

    if (route.kind === "readMessages") {
      const params = parseReadParams(req.query);
      if (!params) {
        res.status(400).json({ error: "invalid_query" });
        return;
      }
      let base: FirebaseFirestore.Query = messages;
      if (floor) base = base.where("sentAt", ">=", floor);
      let query: FirebaseFirestore.Query = base
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
      const readable = docs.filter((d) =>
        isReadableByAssistant(d.data(), ownerId, ownSenderId),
      );
      // 見せないメッセージを読み飛ばした分もカーソルは進める。
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
        messages: readable.map((d) =>
          messageJson(d.id, d.data(), ownSenderId),
        ),
        nextCursor,
      });
      return;
    }

    if (route.kind === "deleteMessage") {
      // 取り消せるのは、このAIエージェント連携自身の投稿だけ。
      const messageDoc = messages.doc(route.messageId);
      const targetData = (await messageDoc.get()).data();
      if (!targetData || targetData.senderId !== ownSenderId) {
        res.status(404).json({ error: "not_found" });
        return;
      }
      const targetSentAt = targetData.sentAt as Timestamp | undefined;
      await messageDoc.delete();
      // 取り消したのが語らい一覧の最終メッセージなら、残った最新のものへ直す。
      if (
        targetSentAt &&
        (conv.lastMessageAt as Timestamp | undefined)?.isEqual(targetSentAt) &&
        conv.lastMessageSenderId === ownSenderId
      ) {
        await refreshLastMessage(convDocRef);
      }
      await audit("deleteBotMessage", {
        botId,
        actorId: ownSenderId,
        ...(scope === "group"
          ? { groupId: conversationId }
          : { dmId: conversationId }),
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
      // 引用できるのは、所有者が読めるメッセージだけ（他のAIエージェント連携の投稿は引用元にしない）。
      const targetSentAt = target?.sentAt as Timestamp | undefined;
      if (
        !target ||
        !targetSentAt ||
        (floor !== null && targetSentAt.toMillis() < floor.toMillis()) ||
        !isReadableByAssistant(target, ownerId, ownSenderId)
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

    // メンション（個人のみ）。その会話のメンバー（所有者を除く）で、所有者が
    // ブロックしていない相手だけ有効。ラベルは、その会話での相手の呼び名。
    const mentionLabels: string[] = [];
    if (payload.mentionUserIds.length > 0) {
      const memberIds = membersOf(scope, conv);
      for (const userId of payload.mentionUserIds) {
        if (
          userId === ownerId ||
          !memberIds.includes(userId) ||
          (await isBlocked(ownerId, userId))
        ) {
          res.status(400).json({
            error: "invalid_payload",
            message: "メンションできない相手がいます",
          });
          return;
        }
        const label = await memberLabel(userId, conversationId);
        if (!label) {
          res.status(400).json({
            error: "invalid_payload",
            message: "メンションできない相手がいます",
          });
          return;
        }
        mentionLabels.push(label);
      }
    }
    const content = ensureMentionText(payload.content, mentionLabels);
    if (content.length > BOT_CONTENT_MAX_LENGTH) {
      res.status(400).json({
        error: "invalid_payload",
        message: `メンションを加えると${BOT_CONTENT_MAX_LENGTH}文字を超えます`,
      });
      return;
    }

    const messageRef = messages.doc();
    const batch = db().batch();
    batch.set(messageRef, {
      conversationId: roomId,
      conversationType: scope === "group" ? "room" : "dm",
      senderId: ownSenderId,
      senderRhingSeed: null,
      // AI連携の名前だけを保存する。表示は「名前（その語らいでの持ち主の呼び名）」で、
      // 呼び名は住人が後から変えられるため、クライアントが`assistantOwnerId`から表示時に
      // 解決する。所有者本人には通知・未読を出さない（`sendMessageNotification`等が参照）。
      botName: bot.name as string,
      assistantOwnerId: ownerId,
      content,
      contentType: "text",
      // メンションは個人のみ（人間の投稿と同じ形で保存し、通知は`resolveMentionRecipients`が決める）。
      mentionedUserIds: payload.mentionUserIds,
      mentionedRoleIds: [],
      mentionEveryone: false,
      mentionLabels,
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
      lastMessageSenderId: ownSenderId,
      lastMessageContentType: "text",
      lastMessagePreview: previewOf(content),
    });
    await batch.commit();
    res.status(200).json({ ok: true, messageId: messageRef.id });
  },
);
