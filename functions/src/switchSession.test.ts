import assert from "node:assert/strict";
import { test } from "node:test";

import {
  SWITCH_MAX_FAILURES,
  decideSessionOwner,
  evaluateRedeem,
  generateSecret,
  hashSecret,
  isActiveAccount,
  isKiwamiPlan,
  verifySecret,
} from "./switchSession";

const now = 1_000_000;

test("合言葉は毎回違う値で、ハッシュと一致するのは元の値だけ", () => {
  const a = generateSecret();
  const b = generateSecret();
  assert.notEqual(a, b);
  assert.ok(a.length >= 40);
  const hash = hashSecret(a);
  assert.equal(verifySecret(a, hash), true);
  assert.equal(verifySecret(b, hash), false);
  assert.equal(verifySecret("", hash), false);
  assert.equal(verifySecret(a, undefined), false);
  assert.equal(verifySecret(a, "not-hex"), false);
});

test("極みと有効なアカウントの判定", () => {
  assert.equal(isKiwamiPlan({ subscriptionPlan: "kiwami" }), true);
  assert.equal(isKiwamiPlan({ subscriptionPlan: "free" }), false);
  assert.equal(isKiwamiPlan(undefined), false);
  assert.equal(isActiveAccount({}), true); // 欠落はactive扱い
  assert.equal(isActiveAccount({ accountStatus: "active" }), true);
  assert.equal(isActiveAccount({ accountStatus: "suspended" }), false);
  assert.equal(isActiveAccount({ accountStatus: "pendingDeletion" }), false);
  assert.equal(isActiveAccount(undefined), false);
});

test("セッション作成: 極みの本人は自分が所有者（チケット不要）", () => {
  const r = decideSessionOwner({ callerUid: "A", callerIsKiwami: true, nowMs: now });
  assert.deepEqual(r, { ok: true, kiwamiOwnerUid: "A" });
});

test("セッション作成: 極みでない本人は、有効なチケットがあれば発行者が所有者", () => {
  const ticket = { ownerUid: "A", expiresAtMs: now + 1000 };
  const r = decideSessionOwner({
    callerUid: "B",
    callerIsKiwami: false,
    ticket,
    ticketOwnerIsKiwami: true,
    nowMs: now,
  });
  assert.deepEqual(r, { ok: true, kiwamiOwnerUid: "A" });
});

test("セッション作成: チケット無し・期限切れ・自分のチケット・発行者が極みでない場合は拒否", () => {
  const base = { callerUid: "B", callerIsKiwami: false, nowMs: now };
  assert.equal(decideSessionOwner(base).ok, false);
  const expired = decideSessionOwner({
    ...base,
    ticket: { ownerUid: "A", expiresAtMs: now - 1 },
    ticketOwnerIsKiwami: true,
  });
  assert.equal(expired.ok === false && expired.code, "deadline-exceeded");
  const own = decideSessionOwner({
    ...base,
    ticket: { ownerUid: "B", expiresAtMs: now + 1000 },
    ticketOwnerIsKiwami: true,
  });
  assert.equal(own.ok === false && own.code, "permission-denied");
  const lapsed = decideSessionOwner({
    ...base,
    ticket: { ownerUid: "A", expiresAtMs: now + 1000 },
    ticketOwnerIsKiwami: false,
  });
  assert.equal(lapsed.ok === false && lapsed.code, "failed-precondition");
  const noExpiry = decideSessionOwner({
    ...base,
    ticket: { ownerUid: "A" },
    ticketOwnerIsKiwami: true,
  });
  assert.equal(noExpiry.ok, false);
});

function session(secret: string, over: Record<string, unknown> = {}) {
  return {
    secretHash: hashSecret(secret),
    kiwamiOwnerUid: "A",
    expiresAtMs: now + 1000,
    failures: 0,
    revoked: false,
    ...over,
  };
}

const activeFree = { accountStatus: "active", subscriptionPlan: "free" };
const kiwami = { accountStatus: "active", subscriptionPlan: "kiwami" };

test("切り替え: 所有者が今も極みなら、切り替え先が極みでなくても通る", () => {
  const secret = generateSecret();
  const r = evaluateRedeem({
    session: session(secret),
    secret,
    nowMs: now,
    targetUser: activeFree,
    ownerUser: kiwami,
  });
  assert.deepEqual(r, { kind: "ok" });
});

test("切り替え: 所有者の極みが切れても、切り替え先自身が極みなら通る", () => {
  const secret = generateSecret();
  const r = evaluateRedeem({
    session: session(secret),
    secret,
    nowMs: now,
    targetUser: kiwami,
    ownerUser: activeFree,
  });
  assert.deepEqual(r, { kind: "ok" });
});

test("切り替え: 所有者も切り替え先も極みでなければ止まる（切り替えだけ止める）", () => {
  const secret = generateSecret();
  const r = evaluateRedeem({
    session: session(secret),
    secret,
    nowMs: now,
    targetUser: activeFree,
    ownerUser: activeFree,
  });
  assert.equal(r.kind, "deny");
  assert.equal(r.kind === "deny" && r.code, "failed-precondition");
});

test("切り替え: 停止中・削除申請中のアカウントは、極みでも拒否する", () => {
  const secret = generateSecret();
  for (const accountStatus of ["suspended", "pendingDeletion"]) {
    const r = evaluateRedeem({
      session: session(secret),
      secret,
      nowMs: now,
      targetUser: { accountStatus, subscriptionPlan: "kiwami" },
      ownerUser: kiwami,
    });
    assert.equal(r.kind, "deny");
  }
});

test("切り替え: 合言葉が違うと失敗を数え、上限に達する回で失効させる", () => {
  const secret = generateSecret();
  const wrong = evaluateRedeem({
    session: session(secret, { failures: 0 }),
    secret: "wrong",
    nowMs: now,
    targetUser: kiwami,
    ownerUser: kiwami,
  });
  assert.deepEqual(wrong, { kind: "badSecret", revoke: false });
  const last = evaluateRedeem({
    session: session(secret, { failures: SWITCH_MAX_FAILURES - 1 }),
    secret: "wrong",
    nowMs: now,
    targetUser: kiwami,
    ownerUser: kiwami,
  });
  assert.deepEqual(last, { kind: "badSecret", revoke: true });
  const locked = evaluateRedeem({
    session: session(secret, { failures: SWITCH_MAX_FAILURES }),
    secret,
    nowMs: now,
    targetUser: kiwami,
    ownerUser: kiwami,
  });
  assert.equal(locked.kind, "deny");
});

test("切り替え: 無い・失効・期限切れのセッションは、同じ文言で拒否する", () => {
  const secret = generateSecret();
  const args = { secret, nowMs: now, targetUser: kiwami, ownerUser: kiwami };
  const none = evaluateRedeem({ ...args, session: undefined });
  const revoked = evaluateRedeem({ ...args, session: session(secret, { revoked: true }) });
  const expired = evaluateRedeem({
    ...args,
    session: session(secret, { expiresAtMs: now - 1 }),
  });
  for (const r of [none, revoked, expired]) assert.equal(r.kind, "deny");
  assert.deepEqual(none, revoked);
  assert.deepEqual(none, expired);
});
