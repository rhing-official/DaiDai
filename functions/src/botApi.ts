import { createHash, randomBytes, timingSafeEqual } from "crypto";

/**
 * bot API（AIが寄合のメッセージを読み、返信できる、2026-11-09追加・段階2a）の
 * 純粋なロジック。Firestore・HTTPには依存させず、単体テスト（`botApi.test.ts`）
 * できる形にしてある（自前化の方針: Firebase固有の層と処理本体を分ける）。
 * 設計は`文書/botAPI設計.md`。
 */

/** 住人1人が作れるbotの最大数。 */
export const BOT_MAX_PER_OWNER = 5;

/** botの名前（BOT名として表示される）の最大文字数。 */
export const BOT_NAME_MAX_LENGTH = 40;

/** 投稿本文の最大文字数。 */
export const BOT_CONTENT_MAX_LENGTH = 2000;

/** 1回の投稿でメンションできる個人の上限（AIの暴走で大勢を呼ばない為）。 */
export const BOT_MENTION_MAX = 5;

/** 取得1回あたりの既定・最大件数。 */
export const BOT_READ_DEFAULT_LIMIT = 50;
export const BOT_READ_MAX_LIMIT = 100;

/** ロングポーリングで待つ最大秒数（Cloud Functionsの実行時間内に収める）。 */
export const BOT_WAIT_MAX_SECONDS = 25;

/** bot由来のメッセージの`senderId`（`users`ドキュメントは存在しない）。 */
export const BOT_SENDER_PREFIX = "bot:";

export function botSenderId(botId: string): string {
  return `${BOT_SENDER_PREFIX}${botId}`;
}

/**
 * botのトークン。`{botId}.{秘密}`の形で、botIdを含めることで認証時に
 * 該当のbotだけを1回の読み取りで引ける（全件走査をしない）。
 */
export function generateBotToken(botId: string): string {
  return `${botId}.${randomBytes(32).toString("base64url")}`;
}

/** 保存用のトークンのハッシュ（平文は保存しない）。 */
export function hashBotToken(token: string): string {
  return createHash("sha256").update(token).digest("hex");
}

/** [token]のハッシュが保存済みの[storedHash]と一致するか（定数時間比較）。 */
export function verifyBotToken(token: string, storedHash: unknown): boolean {
  if (typeof storedHash !== "string" || storedHash.length !== 64) return false;
  const actual = Buffer.from(hashBotToken(token), "hex");
  const expected = Buffer.from(storedHash, "hex");
  if (actual.length !== expected.length) return false;
  return timingSafeEqual(actual, expected);
}

/** `Authorization: Bot <token>`ヘッダーからトークンとbotIdを取り出す。 */
export function parseBotAuthorization(
  header: unknown,
): { token: string; botId: string } | null {
  if (typeof header !== "string") return null;
  const match = /^Bot\s+(\S+)$/.exec(header.trim());
  if (!match) return null;
  const token = match[1];
  const dot = token.indexOf(".");
  if (dot <= 0 || dot === token.length - 1) return null;
  const botId = token.slice(0, dot);
  if (!/^[A-Za-z0-9_-]{1,128}$/.test(botId)) return null;
  return { token, botId };
}

/** botの名前を検証して整える。不正ならnull。 */
export function normalizeBotName(name: unknown): string | null {
  if (typeof name !== "string") return null;
  const trimmed = name.trim();
  if (trimmed.length === 0 || trimmed.length > BOT_NAME_MAX_LENGTH) {
    return null;
  }
  return trimmed;
}

/** botが入れる会話の種類（広場の寄合、または一対の寄合）。 */
export type BotScope = "group" | "dm";

export type BotRoute =
  | { kind: "me" }
  | { kind: "conversations" }
  | { kind: "updates" }
  | { kind: "members"; scope: BotScope; conversationId: string }
  | { kind: "readMessages"; scope: BotScope; conversationId: string; roomId: string }
  | { kind: "postMessage"; scope: BotScope; conversationId: string; roomId: string }
  | {
      kind: "deleteMessage";
      scope: BotScope;
      conversationId: string;
      roomId: string;
      messageId: string;
    };

const ID = /^[A-Za-z0-9_-]{1,128}$/;

/**
 * リクエストの[method]と[path]から経路を決める。関数名のセグメント
 * （`botApi`）が先頭に付く場合も許容する。該当しなければnull。
 *
 * - `GET /v1/me`
 * - `GET /v1/conversations`
 * - `GET /v1/updates?since=&wait=`（AIエージェント連携のみ、更新のあった会話）
 * - `GET /v1/groups/{groupId}/members`・`GET /v1/dms/{dmId}/members`（メンション先を選ぶための参加者一覧）
 * - `GET|POST /v1/groups/{groupId}/rooms/{roomId}/messages`（広場）
 * - `GET|POST /v1/dms/{dmId}/rooms/{roomId}/messages`（一対）
 * - `DELETE …/messages/{messageId}`（そのbot自身の投稿のみ）
 */
export function parseBotRoute(method: string, path: string): BotRoute | null {
  const segments = path.split("/").filter((s) => s.length > 0);
  if (segments[0] === "botApi") segments.shift();
  if (segments[0] !== "v1") return null;
  const rest = segments.slice(1);
  if (rest.length === 1 && rest[0] === "me" && method === "GET") {
    return { kind: "me" };
  }
  if (rest.length === 1 && rest[0] === "conversations" && method === "GET") {
    return { kind: "conversations" };
  }
  if (rest.length === 1 && rest[0] === "updates" && method === "GET") {
    return { kind: "updates" };
  }
  const scope: BotScope | null =
    rest[0] === "groups" ? "group" : rest[0] === "dms" ? "dm" : null;
  if (
    scope !== null &&
    rest.length === 3 &&
    rest[2] === "members" &&
    method === "GET" &&
    ID.test(rest[1] ?? "")
  ) {
    return { kind: "members", scope, conversationId: rest[1] };
  }
  if (
    scope !== null &&
    rest[2] === "rooms" &&
    rest[4] === "messages" &&
    ID.test(rest[1] ?? "") &&
    ID.test(rest[3] ?? "")
  ) {
    const conversationId = rest[1];
    const roomId = rest[3];
    if (rest.length === 5) {
      if (method === "GET") {
        return { kind: "readMessages", scope, conversationId, roomId };
      }
      if (method === "POST") {
        return { kind: "postMessage", scope, conversationId, roomId };
      }
    }
    if (rest.length === 6 && method === "DELETE" && ID.test(rest[5])) {
      return {
        kind: "deleteMessage",
        scope,
        conversationId,
        roomId,
        messageId: rest[5],
      };
    }
  }
  return null;
}

export interface Cursor {
  seconds: number;
  nanos: number;
  messageId: string;
}

/**
 * 取得位置のカーソル（`{秒}.{ナノ秒}_{メッセージid}`をbase64url）。送信時刻は
 * Firestoreのタイムスタンプの精度（秒＋ナノ秒）のまま持つ（ミリ秒に丸めると
 * 同じメッセージを重複して返す為）。
 */
export function encodeCursor(cursor: Cursor): string {
  return Buffer.from(
    `${cursor.seconds}.${cursor.nanos}_${cursor.messageId}`,
  ).toString("base64url");
}

export function decodeCursor(value: unknown): Cursor | null {
  if (typeof value !== "string" || value.length === 0 || value.length > 256) {
    return null;
  }
  let decoded: string;
  try {
    decoded = Buffer.from(value, "base64url").toString("utf8");
  } catch {
    return null;
  }
  const match = /^(\d{1,12})\.(\d{1,9})_([A-Za-z0-9_-]{1,128})$/.exec(decoded);
  if (!match) return null;
  return {
    seconds: Number(match[1]),
    nanos: Number(match[2]),
    messageId: match[3],
  };
}

export interface ReadParams {
  cursor: Cursor | null;
  limit: number;
  waitSeconds: number;
}

/** 取得のクエリ（`after`・`limit`・`wait`）を検証する。不正ならnull。 */
export function parseReadParams(query: {
  [key: string]: unknown;
}): ReadParams | null {
  let cursor: Cursor | null = null;
  if (query.after !== undefined && query.after !== "") {
    cursor = decodeCursor(query.after);
    if (!cursor) return null;
  }
  const limit = parseIntParam(query.limit, BOT_READ_DEFAULT_LIMIT);
  const waitSeconds = parseIntParam(query.wait, 0);
  if (limit === null || waitSeconds === null) return null;
  return {
    cursor,
    limit: Math.min(Math.max(limit, 1), BOT_READ_MAX_LIMIT),
    waitSeconds: Math.min(Math.max(waitSeconds, 0), BOT_WAIT_MAX_SECONDS),
  };
}

function parseIntParam(value: unknown, fallback: number): number | null {
  if (value === undefined || value === "") return fallback;
  if (typeof value !== "string" || !/^\d{1,6}$/.test(value)) return null;
  return Number(value);
}

export type PostPayload =
  | {
      ok: true;
      content: string;
      replyToMessageId: string | null;
      silent: boolean;
      /** メンション先の個人のuserId（重複除去済み、最大[BOT_MENTION_MAX]件）。 */
      mentionUserIds: string[];
    }
  | { ok: false; reason: string };

/** 投稿のJSONボディを検証する。 */
export function parseBotPostPayload(body: unknown): PostPayload {
  if (typeof body !== "object" || body === null || Array.isArray(body)) {
    return { ok: false, reason: "JSONオブジェクトで送ってください" };
  }
  const { content, replyToMessageId, silent, mentions } = body as Record<
    string,
    unknown
  >;
  if (typeof content !== "string") {
    return { ok: false, reason: "contentは文字列で指定してください" };
  }
  if (content.trim().length === 0) {
    return { ok: false, reason: "contentが空です" };
  }
  if (content.length > BOT_CONTENT_MAX_LENGTH) {
    return {
      ok: false,
      reason: `contentは${BOT_CONTENT_MAX_LENGTH}文字以内にしてください`,
    };
  }
  if (
    replyToMessageId !== undefined &&
    replyToMessageId !== null &&
    (typeof replyToMessageId !== "string" || !ID.test(replyToMessageId))
  ) {
    return { ok: false, reason: "replyToMessageIdが正しくありません" };
  }
  if (silent !== undefined && typeof silent !== "boolean") {
    return { ok: false, reason: "silentは真偽値で指定してください" };
  }
  // メンションは個人のみ（`@everyone`・ロール宛は受け付けない）。
  let mentionUserIds: string[] = [];
  if (mentions !== undefined && mentions !== null) {
    const userIds = (mentions as Record<string, unknown>)?.userIds;
    if (
      typeof mentions !== "object" ||
      Array.isArray(mentions) ||
      (userIds !== undefined &&
        (!Array.isArray(userIds) ||
          userIds.some((id) => typeof id !== "string" || !ID.test(id))))
    ) {
      return {
        ok: false,
        reason: "mentions.userIdsはuserIdの配列で指定してください",
      };
    }
    mentionUserIds = [...new Set((userIds as string[] | undefined) ?? [])];
    if (mentionUserIds.length > BOT_MENTION_MAX) {
      return {
        ok: false,
        reason: `メンションは${BOT_MENTION_MAX}人までです`,
      };
    }
  }
  return {
    ok: true,
    content,
    replyToMessageId: (replyToMessageId as string | null | undefined) ?? null,
    silent: silent === true,
    mentionUserIds,
  };
}

/**
 * 本文に`@表示名`が無いメンション先は、本文の先頭に`@表示名 `を補う（本文とメンション先を
 * 食い違わせない。クライアントの入力欄は、本文から`@名前`が消えると宛先から外す）。
 * [labels]は`@`を除いた表示名。
 */
export function ensureMentionText(content: string, labels: string[]): string {
  const missing = labels.filter((l) => !content.includes(`@${l}`));
  if (missing.length === 0) return content;
  return `${missing.map((l) => `@${l}`).join(" ")} ${content}`;
}

/**
 * 持ち主が画面で見ている相手の名前（2026-11-10）。クライアントの`resolveDisplayName`
 * （`lib/utils/contact_alias.dart`）と同じ規則: 自分が付けた呼び名 > その語らいでの
 * 相手の呼び名 > `@Rhing Seed`。空白だけの値は無いものとして扱う。
 */
export function resolveOwnerViewName(input: {
  alias?: string | null;
  nickname?: string | null;
  rhingSeed?: string | null;
}): string | null {
  const alias = input.alias?.trim();
  if (alias) return alias;
  const nickname = input.nickname?.trim();
  if (nickname) return nickname;
  const seed = input.rhingSeed?.trim();
  return seed ? `@${seed}` : null;
}

/** 一覧の最終メッセージの控え（プレビュー）。改行は空白に、80字で切る。 */
export function previewOf(content: string): string {
  const singleLine = content.replace(/\n/g, " ");
  return singleLine.length <= 80 ? singleLine : `${singleLine.slice(0, 80)}…`;
}

/** 返信先の引用プレビュー（本文を空白に畳んで先頭を切る）。 */
export function snippetOf(content: string): string {
  return previewOf(content).slice(0, 60);
}

/**
 * AIエージェント連携のトークン（AIエージェント連携）は、所有者が参加している全ての広場・一対を
 * 扱う（会話ごとの追加・相手の同意は不要、2026-11-09に会話ごとのBOTから一本化）。
 * 保存時の`kind`の値。
 */
export const ASSISTANT_KIND = "assistant";

export interface UpdatesParams {
  sinceMs: number;
  waitSeconds: number;
}

/** 更新の取得のクエリ（`since`＝前回の`nextSince`のミリ秒、`wait`）。不正ならnull。 */
export function parseUpdatesParams(query: {
  [key: string]: unknown;
}): UpdatesParams | null {
  const since = query.since;
  let sinceMs = 0;
  if (since !== undefined && since !== "") {
    if (typeof since !== "string" || !/^\d{1,16}$/.test(since)) return null;
    sinceMs = Number(since);
  }
  const parsed = parseReadParams({ wait: query.wait });
  if (!parsed) return null;
  return { sinceMs, waitSeconds: parsed.waitSeconds };
}

/**
 * AIエージェント連携が寄合のメッセージを読める下限時刻（Firestoreのタイムスタンプ）。
 * 所有者本人が画面で見られる範囲と同じにする（`firestore.rules`の
 * `canReadRoomMessage`と同じ判定）: 広場の「新規メンバーに過去を見せない」設定が
 * 有効なら加入時刻以降、無効（または既存メンバー）なら制限なし（null）。
 */
export function assistantHistoryFloor(
  group: FirebaseFirestore.DocumentData,
  room: FirebaseFirestore.DocumentData,
  ownerId: string,
): unknown {
  const joinedAt = group.memberJoinedAt?.[ownerId] ?? null;
  const hasOverride =
    room.customSettingsEnabled === true &&
    room.historyVisibleOverride !== undefined &&
    room.historyVisibleOverride !== null;
  const visible = hasOverride
    ? room.historyVisibleOverride === true
    : group.historyVisibleToNewMembers === true;
  return joinedAt !== null && !visible ? joinedAt : null;
}

/**
 * AIに見せてよいメッセージか。所有者が非表示にしたもの・スパムは除く。他のAIエージェント連携
 * （bot）の投稿は、AI同士が返信し合うループを防ぐため、自分の投稿以外は見せない。
 */
export function isReadableByAssistant(
  message: { isSpam?: unknown; hiddenFor?: unknown; senderId?: unknown },
  ownerId: string,
  ownSenderId: string,
): boolean {
  if (message.isSpam === true) return false;
  if (Array.isArray(message.hiddenFor) && message.hiddenFor.includes(ownerId)) {
    return false;
  }
  const senderId = typeof message.senderId === "string" ? message.senderId : "";
  return !senderId.startsWith(BOT_SENDER_PREFIX) || senderId === ownSenderId;
}
