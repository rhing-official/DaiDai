import assert from "node:assert/strict";
import { test } from "node:test";

import {
  BULK_SUSPEND_MAX,
  PROFILE_VIEW_NOTE_MAX_LENGTH,
  classifyTarget,
  normalizeBulkTargets,
  parseProfileViewRequest,
} from "./adminUsers";

test("一括対象: 自分・重複・不正値を除き、理由つきで返す", () => {
  const r = normalizeBulkTargets(["a", "b", "me", "a", "", 5], "me");
  assert.equal(r.ok, true);
  if (!r.ok) return;
  assert.deepEqual(r.ids, ["a", "b"]);
  assert.deepEqual(r.skipped, [
    { id: "me", reason: "self" },
    { id: "a", reason: "duplicate" },
    { id: "", reason: "invalid" },
    { id: "5", reason: "invalid" },
  ]);
});

test("一括対象: 配列でない・空・上限超過は拒否する", () => {
  assert.equal(normalizeBulkTargets("a", "me").ok, false);
  assert.equal(normalizeBulkTargets([], "me").ok, false);
  const max = Array.from({ length: BULK_SUSPEND_MAX }, (_, i) => `u${i}`);
  assert.equal(normalizeBulkTargets(max, "me").ok, true);
  assert.equal(normalizeBulkTargets([...max, "extra"], "me").ok, false);
});

test("対象の判定: 不在・削除申請中は常にスキップ、管理者は停止時のみスキップ", () => {
  assert.equal(classifyTarget(undefined, true, false), "not-found");
  assert.equal(
    classifyTarget({ accountStatus: "pendingDeletion" }, false, false),
    "pending-deletion",
  );
  assert.equal(classifyTarget({ accountStatus: "active" }, true, true), "admin");
  assert.equal(classifyTarget({ accountStatus: "suspended" }, false, true), null);
  assert.equal(classifyTarget({ accountStatus: "active" }, true, false), null);
});

test("プロフィール確認の記録リクエストの検証", () => {
  assert.deepEqual(
    parseProfileViewRequest({ targetUserId: "u1", reason: "report", note: " 通報 " }),
    { ok: true, targetUserId: "u1", reason: "report", note: "通報" },
  );
  assert.deepEqual(parseProfileViewRequest({ targetUserId: "u1", reason: "other" }), {
    ok: true,
    targetUserId: "u1",
    reason: "other",
    note: "",
  });
  assert.equal(parseProfileViewRequest(null).ok, false);
  assert.equal(parseProfileViewRequest({ reason: "report" }).ok, false);
  assert.equal(parseProfileViewRequest({ targetUserId: "u1", reason: "x" }).ok, false);
  assert.equal(
    parseProfileViewRequest({ targetUserId: "u1", reason: "other", note: 1 }).ok,
    false,
  );
  assert.equal(
    parseProfileViewRequest({
      targetUserId: "u1",
      reason: "other",
      note: "x".repeat(PROFILE_VIEW_NOTE_MAX_LENGTH + 1),
    }).ok,
    false,
  );
});
