import assert from "node:assert/strict";
import { test } from "node:test";

import {
  SEVERANCE_NOTIFY_COOLDOWN_MS,
  severanceNotifyTarget,
} from "./severanceNotify";

const p = ["a", "b"];
const NOW = 10_000_000_000;

test("未設定→uidで、提案者でない参加者が宛先", () => {
  assert.deepEqual(
    severanceNotifyTarget({}, { severanceRequestedBy: "a", participants: p }, null, NOW),
    { proposerId: "a", recipientId: "b" },
  );
});

test("取り消し・同じ値・無関係な更新は不発", () => {
  assert.equal(
    severanceNotifyTarget({ severanceRequestedBy: "a" }, { severanceRequestedBy: null, participants: p }, null, NOW),
    null,
  );
  assert.equal(
    severanceNotifyTarget({ severanceRequestedBy: "a" }, { severanceRequestedBy: "a", participants: p }, null, NOW),
    null,
  );
  assert.equal(severanceNotifyTarget({}, { participants: p }, null, NOW), null);
});

test("クールダウン内は不発、超えたら発火", () => {
  const after = { severanceRequestedBy: "a", participants: p };
  assert.equal(
    severanceNotifyTarget({}, after, NOW - SEVERANCE_NOTIFY_COOLDOWN_MS + 1, NOW),
    null,
  );
  assert.notEqual(
    severanceNotifyTarget({}, after, NOW - SEVERANCE_NOTIFY_COOLDOWN_MS, NOW),
    null,
  );
});

test("参加者が欠けていれば不発", () => {
  assert.equal(
    severanceNotifyTarget({}, { severanceRequestedBy: "a" }, null, NOW),
    null,
  );
});
