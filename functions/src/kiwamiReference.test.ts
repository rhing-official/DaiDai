import assert from "node:assert/strict";
import { test } from "node:test";

import { parseKiwamiReference } from "./kiwamiReference";

test("uid__経路: 経路を取り出す", () => {
  assert.deepEqual(parseKiwamiReference("abc123__appStore"), {
    uid: "abc123",
    channel: "appStore",
  });
  assert.deepEqual(parseKiwamiReference("abc123__googlePlay"), {
    uid: "abc123",
    channel: "googlePlay",
  });
  assert.deepEqual(parseKiwamiReference("abc123__standard"), {
    uid: "abc123",
    channel: "standard",
  });
});

test("経路が無い（従来のuidだけ）なら標準", () => {
  assert.deepEqual(parseKiwamiReference("abc123"), {
    uid: "abc123",
    channel: "standard",
  });
});

test("知らない経路名は標準、uidは残す", () => {
  assert.deepEqual(parseKiwamiReference("abc123__other"), {
    uid: "abc123",
    channel: "standard",
  });
});

test("空・null・uidが空は、uidなし", () => {
  assert.deepEqual(parseKiwamiReference(""), { uid: null, channel: "standard" });
  assert.deepEqual(parseKiwamiReference(null), { uid: null, channel: "standard" });
  assert.deepEqual(parseKiwamiReference(undefined), { uid: null, channel: "standard" });
  assert.deepEqual(parseKiwamiReference("__appStore"), { uid: null, channel: "standard" });
});
