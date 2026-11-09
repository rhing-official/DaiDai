import assert from "node:assert/strict";
import { test } from "node:test";

import { DaiDaiApiError, DaiDaiClient, conversationPath } from "./api.mjs";

function fakeFetch(responses) {
  const calls = [];
  const impl = async (url, init) => {
    calls.push({ url: String(url), init });
    const r = responses.shift() ?? { status: 200, body: {} };
    return { ok: r.status < 400, status: r.status, json: async () => r.body };
  };
  return { impl, calls };
}

test("経路: 広場と一対で種類が変わり、idはエスケープされる", () => {
  assert.equal(conversationPath("group", "g1", "r1"), "groups/g1/rooms/r1/messages");
  assert.equal(conversationPath("dm", "d1", "r 1"), "dms/d1/rooms/r%201/messages");
  assert.throws(() => conversationPath("x", "a", "b"));
});

test("トークンが無ければ作れない", () => {
  assert.throws(() => new DaiDaiClient({ token: "" }));
});

test("読み取り: 認証ヘッダーとクエリが付く（空の値は付けない）", async () => {
  const { impl, calls } = fakeFetch([{ status: 200, body: { messages: [] } }]);
  const c = new DaiDaiClient({ token: "b.s", baseUrl: "https://x.test/v1/", fetchImpl: impl });
  await c.readMessages({ scope: "group", conversationId: "g", roomId: "r", after: "AAA", wait: 5 });
  assert.equal(calls[0].url, "https://x.test/v1/groups/g/rooms/r/messages?after=AAA&wait=5");
  assert.equal(calls[0].init.headers.Authorization, "Bot b.s");
  assert.equal(calls[0].init.method, "GET");
});

test("投稿: JSONボディで送る", async () => {
  const { impl, calls } = fakeFetch([{ status: 200, body: { ok: true } }]);
  const c = new DaiDaiClient({ token: "t.s", fetchImpl: impl });
  await c.postMessage({
    scope: "dm", conversationId: "d", roomId: "r", content: "hi", replyToMessageId: "m1",
  });
  assert.equal(calls[0].init.method, "POST");
  assert.deepEqual(JSON.parse(calls[0].init.body), { content: "hi", replyToMessageId: "m1" });
  assert.equal(calls[0].init.headers["Content-Type"], "application/json");
});

test("エラー応答はDaiDaiApiErrorになる", async () => {
  const { impl } = fakeFetch([{ status: 403, body: { error: "forbidden" } }]);
  const c = new DaiDaiClient({ token: "t.s", fetchImpl: impl });
  await assert.rejects(
    c.conversations(),
    (e) => e instanceof DaiDaiApiError && e.status === 403 && /forbidden/.test(e.message),
  );
});

test("更新の取得: sinceとwaitが付く", async () => {
  const { impl, calls } = fakeFetch([{ status: 200, body: { conversations: [] } }]);
  const c = new DaiDaiClient({ token: "t.s", baseUrl: "https://x.test/v1", fetchImpl: impl });
  await c.updates({ since: "123", wait: 10 });
  assert.equal(calls[0].url, "https://x.test/v1/updates?since=123&wait=10");
});
