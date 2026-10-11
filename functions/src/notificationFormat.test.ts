import assert from "node:assert/strict";
import { test } from "node:test";

import { formatJstTime, withSenderName, withSentTime } from "./notificationFormat";

test("日本時間の24時間表記（UTCとの差9時間、0時は00）", () => {
  assert.equal(formatJstTime(Date.UTC(2026, 9, 11, 5, 32)), "14:32");
  assert.equal(formatJstTime(Date.UTC(2026, 9, 10, 15, 5)), "00:05");
});

test("本文の先頭に時刻・送信者名を付ける", () => {
  assert.equal(withSentTime("こんにちは", Date.UTC(2026, 9, 11, 5, 32)), "14:32｜こんにちは");
  assert.equal(withSenderName("こんにちは", "山田"), "山田: こんにちは");
  assert.equal(withSenderName("こんにちは", ""), "こんにちは");
});
