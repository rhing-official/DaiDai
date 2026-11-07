import assert from "node:assert/strict";
import { test } from "node:test";

import {
  evaluateSeedChange,
  SEED_ALIAS_DAYS,
  SEED_CHANGE_INTERVAL_DAYS,
  type SeedChangeInput,
} from "./rhingSeedChange";

const DAY = 24 * 60 * 60 * 1000;
const NOW = Date.UTC(2026, 10, 7);

const base: SeedChangeInput = {
  newSeed: "New.Seed",
  currentSeed: "old",
  lastChangedAtMs: null,
  nowMs: NOW,
  takenByOther: false,
  alias: null,
  uid: "u1",
};

test("正常: 小文字化して通す", () => {
  const r = evaluateSeedChange(base);
  assert.equal(r.ok, true);
  if (r.ok) assert.equal(r.newSeed, "new.seed");
});

test("形式違反・予約語・現在と同じは拒否", () => {
  for (const newSeed of ["", "a b", "あ", "x".repeat(21), "Admin", "tayori", "OLD"]) {
    assert.equal(evaluateSeedChange({ ...base, newSeed }).ok, false, newSeed);
  }
});

test("100日未満は拒否、100日ちょうどは許可", () => {
  const recent = evaluateSeedChange({
    ...base,
    lastChangedAtMs: NOW - (SEED_CHANGE_INTERVAL_DAYS - 1) * DAY,
  });
  assert.equal(recent.ok, false);
  if (!recent.ok) assert.equal(recent.error.code, "failed-precondition");
  const enough = evaluateSeedChange({
    ...base,
    lastChangedAtMs: NOW - SEED_CHANGE_INTERVAL_DAYS * DAY,
  });
  assert.equal(enough.ok, true);
});

test("他人が使用中、他人の旧Seed予約中は拒否", () => {
  assert.equal(evaluateSeedChange({ ...base, takenByOther: true }).ok, false);
  assert.equal(
    evaluateSeedChange({
      ...base,
      alias: { uid: "other", expiresAtMs: NOW + DAY },
    }).ok,
    false,
  );
});

test("期限切れの予約は取得でき、自分の旧Seedへは戻せる", () => {
  assert.equal(
    evaluateSeedChange({
      ...base,
      alias: { uid: "other", expiresAtMs: NOW - 1 },
    }).ok,
    true,
  );
  const own = evaluateSeedChange({
    ...base,
    alias: { uid: "u1", expiresAtMs: NOW + SEED_ALIAS_DAYS * DAY },
  });
  assert.equal(own.ok, true);
  if (own.ok) assert.equal(own.restoringOwnAlias, true);
});
