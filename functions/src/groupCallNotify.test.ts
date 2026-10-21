import assert from "node:assert/strict";
import { test } from "node:test";

import {
  groupCallNotificationBody,
  groupCallRecipients,
} from "./groupCallNotify";

test("開始者を除き、重複を1回にする", () => {
  assert.deepEqual(groupCallRecipients(["a", "b", "b", "c"], "a"), ["b", "c"]);
  assert.deepEqual(groupCallRecipients(["a"], "a"), []);
});

test("想定外の形は空・文字列以外は捨てる", () => {
  assert.deepEqual(groupCallRecipients(undefined, "a"), []);
  assert.deepEqual(groupCallRecipients("x", "a"), []);
  assert.deepEqual(groupCallRecipients([1, null, "b"], "a"), ["b"]);
});

test("本文: 名前の有無と、ビデオかどうか", () => {
  assert.equal(groupCallNotificationBody("山田", false), "山田が通話を始めました");
  assert.equal(
    groupCallNotificationBody("山田", true),
    "山田がビデオ通話を始めました",
  );
  assert.equal(groupCallNotificationBody("", false), "通話が始まりました");
  assert.equal(groupCallNotificationBody("", true), "ビデオ通話が始まりました");
});
