import assert from "node:assert/strict";
import { test } from "node:test";

import { dmCallRecordResult, groupCallRecordResult } from "./callRecordResult";

test("一対: 応答後は通話、応答前に発信側が切ればキャンセル、拒否・時間切れは不在着信", () => {
  assert.equal(dmCallRecordResult("active", "ended"), "completed");
  assert.equal(dmCallRecordResult("ringing", "ended"), "cancelled");
  assert.equal(dmCallRecordResult("ringing", "declined"), "missed");
  assert.equal(dmCallRecordResult("ringing", "missed"), "missed");
  assert.equal(dmCallRecordResult("active", "missed"), "missed");
});

test("広場: 誰も入らず呼び出しの間に終わればキャンセル、後なら不在着信", () => {
  const base = { joinedUserIds: ["a"], initiatorId: "a", createdAtMs: 1000 };
  assert.equal(groupCallRecordResult({ ...base, endedAtMs: 1000 + 5000 }), "cancelled");
  assert.equal(groupCallRecordResult({ ...base, endedAtMs: 1000 + 35000 }), "cancelled");
  assert.equal(groupCallRecordResult({ ...base, endedAtMs: 1000 + 35001 }), "missed");
});

test("広場: 誰かが入っていれば通話。参加の記録が無い古い通話も通話", () => {
  assert.equal(
    groupCallRecordResult({
      joinedUserIds: ["a", "b"],
      initiatorId: "a",
      createdAtMs: 0,
      endedAtMs: 1000,
    }),
    "completed",
  );
  assert.equal(
    groupCallRecordResult({
      joinedUserIds: undefined,
      initiatorId: "a",
      createdAtMs: 0,
      endedAtMs: 1000,
    }),
    "completed",
  );
});

test("広場: 作成時刻が不明なら、呼び出し時間は測れないので不在着信", () => {
  assert.equal(
    groupCallRecordResult({
      joinedUserIds: ["a"],
      initiatorId: "a",
      createdAtMs: null,
      endedAtMs: 1000,
    }),
    "missed",
  );
});
