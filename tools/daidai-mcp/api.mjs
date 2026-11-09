/**
 * DaiDai bot API（REST、`Authorization: Bot <token>`）の薄いクライアント。
 * MCPには依存させず、単体テスト（`api.test.mjs`）できる形にしてある。
 */

export const DEFAULT_API_BASE =
  "https://asia-northeast1-daidai-rhing.cloudfunctions.net/botApi/v1";

export class DaiDaiApiError extends Error {
  constructor(status, body) {
    super(`DaiDai API error ${status}: ${body?.error ?? "unknown"}`);
    this.status = status;
    this.body = body;
  }
}

/** 会話の種類（`group`＝広場、`dm`＝一対）から、APIの経路の一部を作る。 */
export function conversationPath(scope, conversationId, roomId) {
  if (scope !== "group" && scope !== "dm") {
    throw new Error('scopeは "group" か "dm" を指定してください');
  }
  const kind = scope === "group" ? "groups" : "dms";
  return `${kind}/${encodeURIComponent(conversationId)}/rooms/${encodeURIComponent(roomId)}/messages`;
}

export class DaiDaiClient {
  constructor({ token, baseUrl = DEFAULT_API_BASE, fetchImpl = fetch }) {
    if (!token) throw new Error("DAIDAI_BOT_TOKEN が設定されていません");
    this.token = token;
    this.baseUrl = baseUrl.replace(/\/+$/, "");
    this.fetch = fetchImpl;
  }

  async #request(method, path, { query, body, signal } = {}) {
    const url = new URL(`${this.baseUrl}/${path}`);
    for (const [k, v] of Object.entries(query ?? {})) {
      if (v !== undefined && v !== null && v !== "") url.searchParams.set(k, String(v));
    }
    const res = await this.fetch(url, {
      method,
      signal,
      headers: {
        Authorization: `Bot ${this.token}`,
        ...(body ? { "Content-Type": "application/json" } : {}),
      },
      body: body ? JSON.stringify(body) : undefined,
    });
    const json = await res.json().catch(() => ({}));
    if (!res.ok) throw new DaiDaiApiError(res.status, json);
    return json;
  }

  me() {
    return this.#request("GET", "me");
  }

  conversations() {
    return this.#request("GET", "conversations");
  }

  /** `after`（前回の`nextCursor`）以降の新着を返す。`wait`秒まで新着を待つ。 */
  readMessages({ scope, conversationId, roomId, after, limit, wait }) {
    return this.#request("GET", conversationPath(scope, conversationId, roomId), {
      query: { after, limit, wait },
    });
  }

  postMessage({ scope, conversationId, roomId, content, replyToMessageId, silent }) {
    return this.#request("POST", conversationPath(scope, conversationId, roomId), {
      body: { content, replyToMessageId, silent },
    });
  }

  deleteMessage({ scope, conversationId, roomId, messageId }) {
    return this.#request(
      "DELETE",
      `${conversationPath(scope, conversationId, roomId)}/${encodeURIComponent(messageId)}`,
    );
  }
}
