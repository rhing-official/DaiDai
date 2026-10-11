import assert from "node:assert/strict";
import { test } from "node:test";

import { excludeBlockers } from "./block";

const blockedBy = (map: Record<string, string[]>) => async (r: string, s: string) =>
  (map[r] ?? []).includes(s);

test("送信者をブロックしている受信者だけ除く", async () => {
  const result = await excludeBlockers(["a", "b"], "s", blockedBy({ a: ["s"], b: ["x"] }));
  assert.deepEqual(result, ["b"]);
});

test("全員ブロックなら空、空入力は空", async () => {
  assert.deepEqual(await excludeBlockers(["a"], "s", blockedBy({ a: ["s"] })), []);
  assert.deepEqual(await excludeBlockers([], "s", blockedBy({})), []);
});
