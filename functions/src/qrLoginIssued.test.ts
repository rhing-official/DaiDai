import assert from "node:assert/strict";
import { test } from "node:test";

import { checkRequest, checkRespond, ISSUED_QR_TTL_MS } from "./qrLoginIssued";

const now = 1_000_000;
const fresh = { mode: "issued", status: "pending", ownerUid: "u1", createdAtMs: now - 1000 };

test("読み取り（要求）は、期限内のpendingなissuedセッションだけ通る", () => {
  assert.deepEqual(checkRequest(fresh, now), { ok: true });
});

test("要求: ゲスト方式のセッション・使用済み・期限切れ・二重要求は拒否する", () => {
  assert.equal(checkRequest({ ...fresh, mode: undefined }, now).ok, false);
  assert.equal(checkRequest({ ...fresh, status: "requested" }, now).ok, false);
  assert.equal(checkRequest({ ...fresh, status: "approved" }, now).ok, false);
  const late = checkRequest({ ...fresh, createdAtMs: now - ISSUED_QR_TTL_MS - 1 }, now);
  assert.equal(late.ok, false);
  assert.equal(late.ok === false && late.code, "deadline-exceeded");
  assert.equal(checkRequest({ ...fresh, createdAtMs: undefined }, now).ok, false);
});

test("許可/拒否は、本人が、要求済みの期限内セッションにだけ返せる", () => {
  const requested = { ...fresh, status: "requested" };
  assert.deepEqual(checkRespond(requested, "u1", now), { ok: true });
  const other = checkRespond(requested, "u2", now);
  assert.equal(other.ok === false && other.code, "permission-denied");
  assert.equal(checkRespond(fresh, "u1", now).ok, false); // まだ要求されていない
  assert.equal(checkRespond({ ...requested, mode: "guest" }, "u1", now).ok, false);
  assert.equal(
    checkRespond({ ...requested, createdAtMs: now - ISSUED_QR_TTL_MS - 1 }, "u1", now).ok,
    false,
  );
});
