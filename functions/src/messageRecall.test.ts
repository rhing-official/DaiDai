import assert from "node:assert/strict";
import { test } from "node:test";

import { recallPayload, recallRecipients } from "./messageRecall";

test("送信者を除き、重複を1回にする", () => {
  assert.deepEqual(recallRecipients(["a", "b", "b", "c"], "a"), ["b", "c"]);
  assert.deepEqual(recallRecipients(["a"], "a"), []);
});

test("想定外の形は空・文字列以外は捨てる", () => {
  assert.deepEqual(recallRecipients(undefined, "a"), []);
  assert.deepEqual(recallRecipients("x", "a"), []);
  assert.deepEqual(recallRecipients([1, null, "b"], "a"), ["b"]);
});

test("合図の中身", () => {
  assert.deepEqual(
    recallPayload({ conversationId: "c", roomId: "r", messageId: "m" }),
    { type: "message_recalled", conversationId: "c", roomId: "r", messageId: "m" },
  );
});
