import assert from "node:assert/strict";
import { test } from "node:test";

import { mergeFcmTokenEntries } from "./fcmTokens";

test("mutedが無い古い登録は、止めていない扱い", () => {
  const result = mergeFcmTokenEntries(undefined, [
    { token: "a", platform: "android" },
    { token: "b", platform: "web" },
  ]);
  assert.deepEqual(result, [
    { token: "a", platform: "android" },
    { token: "b", platform: "web" },
  ]);
});

test("muted: trueのトークンだけ除く", () => {
  const result = mergeFcmTokenEntries(undefined, [
    { token: "a", platform: "android", muted: true },
    { token: "b", platform: "web" },
    { token: "c", platform: "android", muted: false },
  ]);
  assert.deepEqual(result, [
    { token: "b", platform: "web" },
    { token: "c", platform: "android" },
  ]);
});

test("全てのトークンが止まっていれば、送信先は0件", () => {
  const result = mergeFcmTokenEntries(undefined, [
    { token: "a", platform: "android", muted: true },
    { token: "b", platform: "web", muted: true },
  ]);
  assert.deepEqual(result, []);
});

test("旧保存先と重複しても1件にまとめ、新しい保存先の止めた印を優先する", () => {
  const mutedResult = mergeFcmTokenEntries(
    [{ token: "a", platform: "android" }],
    [{ token: "a", platform: "android", muted: true }],
  );
  assert.deepEqual(mutedResult, []);
  const unmutedResult = mergeFcmTokenEntries(
    [{ token: "a", platform: "android", muted: true }],
    [{ token: "a", platform: "android" }],
  );
  assert.deepEqual(unmutedResult, [{ token: "a", platform: "android" }]);
});

test("配列でない・壊れた要素は無視する", () => {
  assert.deepEqual(mergeFcmTokenEntries(null, "x"), []);
  assert.deepEqual(
    mergeFcmTokenEntries(undefined, [null, { token: 1 }, { token: "a" }]),
    [],
  );
});
