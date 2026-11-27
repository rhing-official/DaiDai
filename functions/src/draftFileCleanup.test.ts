import assert from "node:assert/strict";
import { test } from "node:test";

import {
  DRAFT_FILE_MAX_AGE_MS,
  cleanupExpiredDraftFiles,
  selectExpiredDraftFiles,
  type DraftFileStore,
} from "./draftFileCleanup";

const NOW = 1_800_000_000_000;
const DAY = 24 * 60 * 60 * 1000;

test("期限を過ぎたものだけを、古い順に選ぶ", () => {
  const r = selectExpiredDraftFiles(
    [
      { name: "a", createdMillis: NOW - 8 * DAY },
      { name: "b", createdMillis: NOW - 6 * DAY },
      { name: "c", createdMillis: NOW - 30 * DAY },
      { name: "d", createdMillis: NOW - DRAFT_FILE_MAX_AGE_MS },
    ],
    NOW,
  );
  assert.deepEqual(r, ["c", "a"]);
});

test("作成時刻が分からないものは消さない。上限を超える分は残す", () => {
  const r = selectExpiredDraftFiles(
    [
      { name: "x", createdMillis: Number.NaN },
      { name: "y", createdMillis: NOW - 9 * DAY },
      { name: "z", createdMillis: NOW - 10 * DAY },
    ],
    NOW,
    DRAFT_FILE_MAX_AGE_MS,
    1,
  );
  assert.deepEqual(r, ["z"]);
});

test("削除に失敗したものは、failedに入れて、続きを消す", async () => {
  const deletedNames: string[] = [];
  const store: DraftFileStore = {
    async list() {
      return [
        { name: "p", createdMillis: NOW - 9 * DAY },
        { name: "q", createdMillis: NOW - 10 * DAY },
      ];
    },
    async delete(name) {
      if (name === "q") throw new Error("失敗");
      deletedNames.push(name);
    },
  };
  const r = await cleanupExpiredDraftFiles(store, NOW);
  assert.deepEqual(r.deleted, ["p"]);
  assert.deepEqual(r.failed, ["q"]);
  assert.deepEqual(deletedNames, ["p"]);
});
