import assert from "node:assert/strict";
import { test } from "node:test";

import {
  WEBHOOK_CONTENT_MAX_LENGTH,
  WEBHOOK_NAME_MAX_LENGTH,
  WEBHOOK_RATE_LIMIT,
  WEBHOOK_RATE_WINDOW_MS,
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

test("トークンはURLに安全で、毎回異なり、ハッシュで照合できる", () => {
  const a = generateWebhookToken();
  const b = generateWebhookToken();
  assert.notEqual(a, b);
  assert.match(a, /^[A-Za-z0-9_-]{43}$/);
  const hash = hashWebhookToken(a);
  assert.equal(hash.length, 64);
  assert.equal(verifyWebhookToken(a, hash), true);
  assert.equal(verifyWebhookToken(b, hash), false);
  assert.equal(verifyWebhookToken(a, undefined), false);
  assert.equal(verifyWebhookToken(a, "short"), false);
});

test("Webhookの送信者idと名前の検証", () => {
  assert.equal(webhookSenderId("abc"), "webhook:abc");
  assert.equal(normalizeWebhookName("  CI通知  "), "CI通知");
  assert.equal(normalizeWebhookName(""), null);
  assert.equal(normalizeWebhookName("   "), null);
  assert.equal(normalizeWebhookName(123), null);
  assert.equal(normalizeWebhookName("あ".repeat(WEBHOOK_NAME_MAX_LENGTH)), "あ".repeat(WEBHOOK_NAME_MAX_LENGTH));
  assert.equal(normalizeWebhookName("あ".repeat(WEBHOOK_NAME_MAX_LENGTH + 1)), null);
});

test("パスから groupId/webhookId/token を取り出す（関数名のセグメントは任意）", () => {
  assert.deepEqual(parseWebhookPath("/g1/w1/tok-en_1"), {
    groupId: "g1",
    webhookId: "w1",
    token: "tok-en_1",
  });
  assert.deepEqual(parseWebhookPath("/postWebhookMessage/g1/w1/t"), {
    groupId: "g1",
    webhookId: "w1",
    token: "t",
  });
  assert.equal(parseWebhookPath("/g1/w1"), null);
  assert.equal(parseWebhookPath("/g1/w1/t/extra"), null);
  assert.equal(parseWebhookPath("/g1/w1/t%20x"), null);
  assert.equal(parseWebhookPath("/"), null);
});

test("投稿ペイロードの検証", () => {
  assert.deepEqual(parseWebhookPayload({ content: "こんにちは" }), {
    ok: true,
    content: "こんにちは",
    silent: false,
  });
  assert.deepEqual(parseWebhookPayload({ content: "x", silent: true }), {
    ok: true,
    content: "x",
    silent: true,
  });
  assert.equal(parseWebhookPayload(null).ok, false);
  assert.equal(parseWebhookPayload([]).ok, false);
  assert.equal(parseWebhookPayload({}).ok, false);
  assert.equal(parseWebhookPayload({ content: 1 }).ok, false);
  assert.equal(parseWebhookPayload({ content: "   " }).ok, false);
  assert.equal(parseWebhookPayload({ content: "x", silent: "yes" }).ok, false);
  assert.equal(
    parseWebhookPayload({ content: "x".repeat(WEBHOOK_CONTENT_MAX_LENGTH) }).ok,
    true,
  );
  assert.equal(
    parseWebhookPayload({ content: "x".repeat(WEBHOOK_CONTENT_MAX_LENGTH + 1) }).ok,
    false,
  );
});

test("レート制限: 窓内で上限まで許可し、超えたら拒否、窓が切れたら再開", () => {
  let state = { windowStartMs: null as number | null, count: 0 };
  const t0 = 1_000_000;
  for (let i = 0; i < WEBHOOK_RATE_LIMIT; i++) {
    const d = nextRateState(state, t0 + i);
    assert.equal(d.allowed, true);
    state = d;
  }
  assert.equal(state.count, WEBHOOK_RATE_LIMIT);
  const rejected = nextRateState(state, t0 + 1000);
  assert.equal(rejected.allowed, false);
  assert.equal(rejected.count, WEBHOOK_RATE_LIMIT);

  const reopened = nextRateState(state, t0 + WEBHOOK_RATE_WINDOW_MS);
  assert.equal(reopened.allowed, true);
  assert.equal(reopened.count, 1);
  assert.equal(reopened.windowStartMs, t0 + WEBHOOK_RATE_WINDOW_MS);
});

test("管理権限: 長は常に可、それ以外はmanageBotsを持つ人のみ", () => {
  const group = {
    ownerId: "owner",
    memberPermissions: {
      mod: ["manageBots", "createInvite"],
      other: ["createInvite"],
    },
  };
  assert.equal(canManageBots(group, "owner"), true);
  assert.equal(canManageBots(group, "mod"), true);
  assert.equal(canManageBots(group, "other"), false);
  assert.equal(canManageBots(group, "stranger"), false);
  assert.equal(canManageBots(undefined, "owner"), false);
});
