import assert from "node:assert/strict";
import { test } from "node:test";

import {
  ORPHAN_AGE_MS,
  cleanupOrphanSubmissionAssets,
  failureLockedUntil,
  isDailyLimitReached,
  recentFailures,
  selectOrphanDirs,
  type AssetDir,
  type OrphanCleanupStore,
} from "./themePackAbuse";

const NOW = 1_800_000_000_000;
const HOUR = 60 * 60 * 1000;

test("1日の上限: 4回までは通り、5回で止まる", () => {
  assert.equal(isDailyLimitReached(4), false);
  assert.equal(isDailyLimitReached(5), true);
});

test("失敗: 窓の中の最近の10件だけを残す。未来・非数・古い物は捨てる", () => {
  const f = [NOW - 2 * HOUR, NOW - HOUR + 1, NOW + 5000, Number.NaN, ...Array.from({ length: 12 }, (_, i) => NOW - 100 + i)];
  const r = recentFailures(f, NOW);
  assert.equal(r.length, 10);
  assert.ok(r.every((t) => t <= NOW && NOW - t < HOUR));
});

test("失敗: 10回で止まり、最後の失敗から1時間で解除", () => {
  const nine = Array.from({ length: 9 }, (_, i) => NOW - 1000 + i);
  assert.equal(failureLockedUntil(nine, NOW), null);
  const ten = [...nine, NOW - 1];
  assert.equal(failureLockedUntil(ten, NOW), NOW - 1 + HOUR);
  assert.equal(failureLockedUntil(ten, NOW - 1 + HOUR), null);
});

test("失敗: 10回でも、1時間より長く散らばっていれば止めない。止めている途中で古い失敗が窓から外れても、期限は変わらない", () => {
  const spread = Array.from({ length: 10 }, (_, i) => NOW - 10 * HOUR + i * HOUR); // 1時間おきの10回
  assert.equal(failureLockedUntil(spread, NOW), null);
  const burst = Array.from({ length: 10 }, (_, i) => NOW - 50 * 60 * 1000 + i); // 50分前に、10回続けて
  assert.equal(failureLockedUntil(burst, NOW), NOW - 50 * 60 * 1000 + 9 + HOUR);
  assert.notEqual(failureLockedUntil(burst, NOW + 5 * 60 * 1000), null); // 窓から外れる頃でも、まだ止まっている
});

const dir = (id: string, ageMs: number): AssetDir => ({ prefix: `themePackSubmissions/u/${id}`, submissionId: id, newestMillis: NOW - ageMs });

test("掃除の対象: 24時間以上たち、文書の無い物だけ", () => {
  const dirs = [dir("old-orphan", ORPHAN_AGE_MS), dir("old-kept", 3 * ORPHAN_AGE_MS), dir("fresh", ORPHAN_AGE_MS - 1)];
  const r = selectOrphanDirs(dirs, new Set(["old-kept"]), NOW);
  assert.deepEqual(r.map((d) => d.submissionId), ["old-orphan"]);
});

class FakeOrphanStore implements OrphanCleanupStore {
  deletedPrefixes: string[] = [];
  failOn = new Set<string>();
  constructor(
    private dirs: AssetDir[],
    private existing: string[],
  ) {}
  async listAssetDirs() {
    return this.dirs;
  }
  async existingSubmissionIds(ids: string[]) {
    return new Set(ids.filter((i) => this.existing.includes(i)));
  }
  async deleteDir(prefix: string) {
    if (this.failOn.has(prefix)) throw new Error("boom");
    this.deletedPrefixes.push(prefix);
  }
}

test("掃除: 対象だけを消し、置いた直後の素材と、文書の有る素材は残す", async () => {
  const s = new FakeOrphanStore([dir("a", 2 * ORPHAN_AGE_MS), dir("b", 2 * ORPHAN_AGE_MS), dir("fresh", HOUR)], ["b"]);
  const r = await cleanupOrphanSubmissionAssets(s, NOW);
  assert.deepEqual(r.deleted, ["themePackSubmissions/u/a"]);
  assert.deepEqual(s.deletedPrefixes, ["themePackSubmissions/u/a"]);
});

test("掃除: 1つの削除に失敗しても、残りを続ける。1回の上限を超えた分は残す", async () => {
  const s = new FakeOrphanStore([dir("a", 2 * ORPHAN_AGE_MS), dir("b", 2 * ORPHAN_AGE_MS), dir("c", 2 * ORPHAN_AGE_MS)], []);
  s.failOn.add("themePackSubmissions/u/a");
  const r = await cleanupOrphanSubmissionAssets(s, NOW, 2);
  assert.deepEqual(r.failed, ["themePackSubmissions/u/a"]);
  assert.deepEqual(r.deleted, ["themePackSubmissions/u/b"]);
  assert.ok(!s.deletedPrefixes.includes("themePackSubmissions/u/c")); // 上限2件のうち、aとbだけを試す
});
