import assert from "node:assert/strict";
import { test } from "node:test";

import {
  DELETE_CHUNK,
  deleteThemePackData,
  isCreatorPackId,
  type AccountDeletionStore,
} from "./themePackAccountDeletion";

const UID = "user-a";

/** Firestore と Storage を、メモリの上で再現する */
class FakeStore implements AccountDeletionStore {
  submissions: { id: string; creatorId: string; packId: string }[] = [];
  packs = new Map<string, { creatorId: string; ownerCount: number }>();
  /** 取得の記録。`${uid}/${packId}` */
  owned = new Set<string>();
  storage = new Set<string>();
  abuse = new Set<string>();
  /** お気に入り・カート。`${uid}/${packId}` */
  favorites = new Set<string>();
  carts = new Set<string>();
  ownedBatchSizes: number[] = [];
  submissionBatchSizes: number[] = [];
  failOnce: string | null = null;
  log: string[] = [];

  private maybeFail(step: string) {
    if (this.failOnce === step) {
      this.failOnce = null;
      throw new Error(`fail at ${step}`);
    }
  }
  async listCreatorPackIds(uid: string) {
    const ids = new Set<string>();
    for (const s of this.submissions) if (s.creatorId === uid) ids.add(s.packId);
    for (const [id, p] of this.packs) if (p.creatorId === uid) ids.add(id);
    return [...ids];
  }
  async deleteOwnedRecords(packId: string, limit: number) {
    this.maybeFail("owned");
    const hit = [...this.owned].filter((k) => k.endsWith(`/${packId}`)).slice(0, limit);
    for (const k of hit) this.owned.delete(k);
    if (hit.length > 0) this.ownedBatchSizes.push(hit.length);
    return hit.length;
  }
  async deletePrefix(prefix: string) {
    this.maybeFail("storage");
    this.log.push(`prefix:${prefix}`);
    for (const k of [...this.storage]) if (k.startsWith(prefix)) this.storage.delete(k);
  }
  async deletePackDoc(packId: string) {
    this.log.push(`packDoc:${packId}`);
    this.packs.delete(packId);
  }
  async deleteSubmissionDocs(uid: string, limit: number) {
    const hit = this.submissions.filter((s) => s.creatorId === uid).slice(0, limit);
    this.submissions = this.submissions.filter((s) => !hit.includes(s));
    if (hit.length > 0) this.submissionBatchSizes.push(hit.length);
    return hit.length;
  }
  async listOwnedPackIds(uid: string) {
    return [...this.owned].filter((k) => k.startsWith(`${uid}/`)).map((k) => k.slice(uid.length + 1));
  }
  async releaseOwnedPack(uid: string, packId: string) {
    const key = `${uid}/${packId}`;
    if (!this.owned.has(key)) return;
    const p = this.packs.get(packId);
    if (p) p.ownerCount = Math.max(0, p.ownerCount - 1);
    this.owned.delete(key);
  }
  private drainSet(set: Set<string>, uid: string, limit: number) {
    const hit = [...set].filter((k) => k.startsWith(`${uid}/`)).slice(0, limit);
    for (const k of hit) set.delete(k);
    return hit.length;
  }
  async deleteFavoriteDesigns(uid: string, limit: number) {
    return this.drainSet(this.favorites, uid, limit);
  }
  async deleteCartDesigns(uid: string, limit: number) {
    return this.drainSet(this.carts, uid, limit);
  }
  async deleteAbuseRecords(uid: string) {
    this.abuse.delete(uid);
  }
}

function seeded() {
  const s = new FakeStore();
  const mine = `${UID}__mine`;
  s.packs.set(mine, { creatorId: UID, ownerCount: 3 });
  s.submissions.push({ id: "s1", creatorId: UID, packId: mine }, { id: "s2", creatorId: UID, packId: mine }, { id: "s3", creatorId: UID, packId: `${UID}__unapproved` });
  s.storage.add(`themePacks/${mine}/1/pack.json`);
  s.storage.add(`themePacks/${mine}/2/pack.json`);
  s.storage.add(`themePackSubmissions/${UID}/s1/pack.json`);
  s.storage.add(`themePackSubmissions/${UID}/orphan/pack.json`); // 提出されなかった素材
  // 他人の物
  s.packs.set("user-b__theirs", { creatorId: "user-b", ownerCount: 5 });
  s.submissions.push({ id: "t1", creatorId: "user-b", packId: "user-b__theirs" });
  s.storage.add("themePacks/user-b__theirs/1/pack.json");
  s.storage.add("themePackSubmissions/user-b/t1/pack.json");
  s.owned.add("user-c/" + mine).add("user-d/" + mine).add(`${UID}/user-b__theirs`);
  s.abuse.add(UID);
  return s;
}

test("投稿者として: 提出文書・公開文書・両方の素材・取得した人の記録を消し、他人の物は残す", async () => {
  const s = seeded();
  await deleteThemePackData(s, UID);
  assert.deepEqual(s.submissions.map((x) => x.id), ["t1"]);
  assert.deepEqual([...s.packs.keys()], ["user-b__theirs"]);
  assert.deepEqual([...s.storage].sort(), ["themePackSubmissions/user-b/t1/pack.json", "themePacks/user-b__theirs/1/pack.json"]);
  assert.ok(![...s.owned].some((k) => k.endsWith(`${UID}__mine`)), "取得した人の記録が消える");
  assert.equal(s.abuse.has(UID), false);
});

test("取得者として: 自分の取得記録を消し、ownerCount を1減らす", async () => {
  const s = seeded();
  await deleteThemePackData(s, UID);
  assert.equal(s.packs.get("user-b__theirs")!.ownerCount, 4);
  assert.ok(![...s.owned].some((k) => k.startsWith(`${UID}/`)));
});

test("取得者として: ownerCount は0未満にならない", async () => {
  const s = new FakeStore();
  s.packs.set("user-b__theirs", { creatorId: "user-b", ownerCount: 0 });
  s.owned.add(`${UID}/user-b__theirs`);
  await deleteThemePackData(s, UID);
  assert.equal(s.packs.get("user-b__theirs")!.ownerCount, 0);
});

test("取得者として: 自作の意匠を自分で取得していても、二重に減らさない（先に投稿者として消える）", async () => {
  const s = new FakeStore();
  s.packs.set(`${UID}__mine`, { creatorId: UID, ownerCount: 1 });
  s.owned.add(`${UID}/${UID}__mine`);
  await deleteThemePackData(s, UID);
  assert.equal(s.packs.size, 0);
  assert.equal(s.owned.size, 0);
});

test("取得した人の記録: 0件・401件（400と1に分ける）", async () => {
  const none = new FakeStore();
  none.packs.set(`${UID}__p`, { creatorId: UID, ownerCount: 0 });
  await deleteThemePackData(none, UID);
  assert.deepEqual(none.ownedBatchSizes, []);

  const many = new FakeStore();
  many.packs.set(`${UID}__p`, { creatorId: UID, ownerCount: 401 });
  for (let i = 0; i < 401; i++) many.owned.add(`holder-${i}/${UID}__p`);
  await deleteThemePackData(many, UID);
  assert.deepEqual(many.ownedBatchSizes, [DELETE_CHUNK, 1]);
  assert.equal(many.owned.size, 0);
});

test("提出文書も400件ずつ消す", async () => {
  const s = new FakeStore();
  for (let i = 0; i < 401; i++) s.submissions.push({ id: `s${i}`, creatorId: UID, packId: `${UID}__p` });
  await deleteThemePackData(s, UID);
  assert.deepEqual(s.submissionBatchSizes, [400, 1]);
});

test("順序: 素材を消してから、手がかりの公開文書・提出文書を消す", async () => {
  const s = seeded();
  await deleteThemePackData(s, UID);
  const iPublicAssets = s.log.indexOf(`prefix:themePacks/${UID}__mine/`);
  const iPackDoc = s.log.indexOf(`packDoc:${UID}__mine`);
  assert.ok(iPublicAssets >= 0 && iPublicAssets < iPackDoc);
});

test("途中で失敗しても、再実行で最後まで消える（公開文書と提出文書は、素材の後に消えるので手がかりが残る）", async () => {
  for (const step of ["owned", "storage"]) {
    const s = seeded();
    s.failOnce = step;
    await assert.rejects(deleteThemePackData(s, UID));
    assert.ok(s.submissions.some((x) => x.creatorId === UID), "失敗の時点では、手がかりの文書が残る");
    await deleteThemePackData(s, UID);
    assert.deepEqual(s.submissions.map((x) => x.id), ["t1"]);
    assert.deepEqual([...s.packs.keys()], ["user-b__theirs"]);
    assert.equal(s.packs.get("user-b__theirs")!.ownerCount, 4);
    assert.ok(![...s.storage].some((k) => k.includes(`/${UID}/`) || k.includes(`${UID}__`)));
  }
});

test("再実行しても、他の人の ownerCount を減らし直さない", async () => {
  const s = seeded();
  await deleteThemePackData(s, UID);
  await deleteThemePackData(s, UID);
  assert.equal(s.packs.get("user-b__theirs")!.ownerCount, 4);
});

test("安全策: 自分の名前空間でない packId は、素材も文書も消さない。uid が不正なら例外", async () => {
  assert.equal(isCreatorPackId(UID, `${UID}__x`), true);
  assert.equal(isCreatorPackId(UID, "user-b__x"), false);
  assert.equal(isCreatorPackId(UID, `${UID}__../x`), false);
  const s = new FakeStore();
  s.submissions.push({ id: "bad", creatorId: UID, packId: "user-b__theirs" }); // 他人の packId を指す不正な文書
  s.packs.set("user-b__theirs", { creatorId: "user-b", ownerCount: 1 });
  s.storage.add("themePacks/user-b__theirs/1/pack.json");
  await deleteThemePackData(s, UID);
  assert.ok(s.packs.has("user-b__theirs"));
  assert.ok(s.storage.has("themePacks/user-b__theirs/1/pack.json"));
  await assert.rejects(deleteThemePackData(s, ""));
  await assert.rejects(deleteThemePackData(s, "a/b"));
});

test("意匠のお気に入り・カート: 401件でも全部消え、他人の分は残り、2回呼んでも壊れない", async () => {
  const s = new FakeStore();
  for (let i = 0; i < 401; i++) {
    s.favorites.add(`${UID}/f${i}`);
    s.carts.add(`${UID}/c${i}`);
  }
  s.favorites.add("user-b/f0");
  s.carts.add("user-b/c0");
  await deleteThemePackData(s, UID);
  assert.deepEqual([...s.favorites], ["user-b/f0"]);
  assert.deepEqual([...s.carts], ["user-b/c0"]);
  await deleteThemePackData(s, UID);
  assert.equal(s.favorites.size, 1);
  assert.equal(s.carts.size, 1);
});
