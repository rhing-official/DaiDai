import assert from "node:assert/strict";
import { test } from "node:test";

import {
  OwnershipError,
  PAID_THEME_PACKS_DISABLED_MESSAGE,
  acquireThemePack,
  uninstallThemePack,
  withdrawThemePack,
  type OwnedPack,
  type OwnershipStore,
  type OwnershipTx,
} from "./themePackOwnership";

const CREATOR = "creator-a";
const ALICE = "alice";
const BOB = "bob";
const PACK = `${CREATOR}__sakura`;
const SID = "11111111-2222-4333-8444-555555555555";

class FakeStore implements OwnershipStore {
  packs = new Map<string, OwnedPack>();
  /** `${uid}/${packId}` → 記録 */
  owned = new Map<string, { packId: string; version: number }>();
  subs = new Map<string, { packId: string; version: number; status: string }>();

  putPack(over: Partial<OwnedPack> = {}) {
    this.packs.set(PACK, { creatorId: CREATOR, version: 1, status: "approved", price: 0, ownerCount: 0, ...over });
  }
  async runTransaction<T>(fn: (tx: OwnershipTx) => Promise<T>): Promise<T> {
    const self = this;
    return fn({
      async getPack(packId) {
        const p = self.packs.get(packId);
        return p ? { ...p } : null;
      },
      async hasOwned(uid, packId) {
        return self.owned.has(`${uid}/${packId}`);
      },
      async findSubmission(packId, version) {
        for (const [id, s] of self.subs) if (s.packId === packId && s.version === version) return { id, status: s.status };
        return null;
      },
      setOwned(uid, packId, version) {
        self.owned.set(`${uid}/${packId}`, { packId, version });
      },
      deleteOwned(uid, packId) {
        self.owned.delete(`${uid}/${packId}`);
      },
      setOwnerCount(packId, count) {
        self.packs.get(packId)!.ownerCount = count;
      },
      setPackStatus(packId, status) {
        self.packs.get(packId)!.status = status;
      },
      setSubmissionStatus(id, status) {
        self.subs.get(id)!.status = status;
      },
    });
  }
}

const acquire = (s: FakeStore, uid: string | undefined, data: unknown, paid = false) =>
  acquireThemePack(s, { uid, data }, { paidPacksEnabled: paid });
const uninstall = (s: FakeStore, uid: string | undefined, data: unknown) => uninstallThemePack(s, { uid, data });
const withdraw = (s: FakeStore, uid: string | undefined, data: unknown) => withdrawThemePack(s, { uid, data });

async function rejects(p: Promise<unknown>, code: string, message?: string) {
  await assert.rejects(p, (e) => e instanceof OwnershipError && e.code === code && (!message || e.message === message));
}

function ready(over: Partial<OwnedPack> = {}): FakeStore {
  const s = new FakeStore();
  s.putPack(over);
  s.subs.set(SID, { packId: PACK, version: over.version ?? 1, status: "approved" });
  return s;
}

// --- 取得 ---------------------------------------------------------------

test("取得: 記録を作り、ownerCountを1増やし、取得時の版を返す", async () => {
  const s = ready({ version: 3 });
  const r = await acquire(s, ALICE, { packId: PACK });
  assert.deepEqual({ ...r }, { packId: PACK, version: 3, alreadyOwned: false });
  assert.deepEqual(s.owned.get(`${ALICE}/${PACK}`), { packId: PACK, version: 3 });
  assert.equal(s.packs.get(PACK)!.ownerCount, 1);
});

test("取得: 二重呼び出しでownerCountが重ならない。alreadyOwned: true で、何も変えない", async () => {
  const s = ready();
  await acquire(s, ALICE, { packId: PACK });
  const again = await acquire(s, ALICE, { packId: PACK });
  assert.equal(again.alreadyOwned, true);
  assert.equal(s.packs.get(PACK)!.ownerCount, 1);
  assert.equal(s.owned.size, 1);
  // 別の人は別に数える
  await acquire(s, BOB, { packId: PACK });
  assert.equal(s.packs.get(PACK)!.ownerCount, 2);
});

test("取得: 公開中の版が後で上がっても、記録の版は変わらない", async () => {
  const s = ready({ version: 1 });
  await acquire(s, ALICE, { packId: PACK });
  s.packs.get(PACK)!.version = 2;
  const again = await acquire(s, ALICE, { packId: PACK });
  assert.equal(again.alreadyOwned, true);
  assert.equal(s.owned.get(`${ALICE}/${PACK}`)!.version, 1);
});

test("取得: approved以外（withdrawn・suspended・その他）は failed-precondition。記録も数も変えない", async () => {
  for (const st of ["withdrawn", "suspended", "submitted"]) {
    const s = ready({ status: st });
    await rejects(acquire(s, ALICE, { packId: PACK }), "failed-precondition");
    assert.equal(s.owned.size, 0);
    assert.equal(s.packs.get(PACK)!.ownerCount, 0);
  }
});

test("取得: 無い意匠は not-found", async () => {
  await rejects(acquire(new FakeStore(), ALICE, { packId: "nope" }), "not-found");
});

test("取得: 有料は、PAID_PACKS_ENABLED=falseの間、拒否する。trueなら取得できる", async () => {
  const s = ready({ price: 300 });
  await rejects(acquire(s, ALICE, { packId: PACK }), "failed-precondition", PAID_THEME_PACKS_DISABLED_MESSAGE);
  assert.equal(s.owned.size, 0);
  assert.equal(s.packs.get(PACK)!.ownerCount, 0);
  const r = await acquire(s, ALICE, { packId: PACK }, true);
  assert.equal(r.alreadyOwned, false);
});

test("取得: 未ログインは unauthenticated、packIdが無い・文字列でないときは invalid-argument", async () => {
  const s = ready();
  await rejects(acquire(s, undefined, { packId: PACK }), "unauthenticated");
  await rejects(acquire(s, ALICE, {}), "invalid-argument");
  await rejects(acquire(s, ALICE, { packId: 1 }), "invalid-argument");
  await rejects(acquire(s, ALICE, null), "invalid-argument");
});

test("取得: 取り下げの後でも、既に持っている人の二重呼び出しは成功し、何も変えない", async () => {
  const s = ready();
  await acquire(s, ALICE, { packId: PACK });
  s.packs.get(PACK)!.status = "withdrawn";
  const again = await acquire(s, ALICE, { packId: PACK });
  assert.equal(again.alreadyOwned, true);
  assert.equal(s.packs.get(PACK)!.ownerCount, 1);
  // 持っていない人は、取得できない
  await rejects(acquire(s, BOB, { packId: PACK }), "failed-precondition");
});

// --- アンインストール -----------------------------------------------------

test("アンインストール: 記録を外し、ownerCountを1減らす", async () => {
  const s = ready();
  await acquire(s, ALICE, { packId: PACK });
  await acquire(s, BOB, { packId: PACK });
  const r = await uninstall(s, ALICE, { packId: PACK });
  assert.deepEqual({ ...r }, { packId: PACK, removed: true });
  assert.equal(s.owned.has(`${ALICE}/${PACK}`), false);
  assert.equal(s.owned.has(`${BOB}/${PACK}`), true);
  assert.equal(s.packs.get(PACK)!.ownerCount, 1);
});

test("アンインストール: 二重呼び出しで減らしすぎない。無ければ何もせず成功", async () => {
  const s = ready();
  await acquire(s, ALICE, { packId: PACK });
  await acquire(s, BOB, { packId: PACK });
  await uninstall(s, ALICE, { packId: PACK });
  const again = await uninstall(s, ALICE, { packId: PACK });
  assert.deepEqual({ ...again }, { packId: PACK, removed: false });
  assert.equal(s.packs.get(PACK)!.ownerCount, 1);
  // 一度も取得していない人
  const never = await uninstall(s, "carol", { packId: PACK });
  assert.equal(never.removed, false);
  assert.equal(s.packs.get(PACK)!.ownerCount, 1);
});

test("アンインストール: ownerCountが0（記録とずれている）でも、0未満にならない", async () => {
  const s = ready({ ownerCount: 0 });
  s.owned.set(`${ALICE}/${PACK}`, { packId: PACK, version: 1 });
  await uninstall(s, ALICE, { packId: PACK });
  assert.equal(s.packs.get(PACK)!.ownerCount, 0);
  assert.equal(s.owned.size, 0);
});

test("アンインストール: 取り下げ・停止の後でも外せる。意匠が消えていても記録は外せる", async () => {
  for (const st of ["withdrawn", "suspended"]) {
    const s = ready();
    await acquire(s, ALICE, { packId: PACK });
    s.packs.get(PACK)!.status = st;
    assert.equal((await uninstall(s, ALICE, { packId: PACK })).removed, true);
    assert.equal(s.packs.get(PACK)!.ownerCount, 0);
  }
  const gone = ready();
  await acquire(gone, ALICE, { packId: PACK });
  gone.packs.delete(PACK);
  assert.equal((await uninstall(gone, ALICE, { packId: PACK })).removed, true);
  assert.equal(gone.owned.size, 0);
});

test("アンインストール: 未ログインは unauthenticated、packIdが無いときは invalid-argument", async () => {
  const s = ready();
  await rejects(uninstall(s, undefined, { packId: PACK }), "unauthenticated");
  await rejects(uninstall(s, ALICE, {}), "invalid-argument");
});

// --- 取り下げ -----------------------------------------------------------

test("取り下げ: 本人が、公開中の意匠を withdrawn にし、現行版の投稿も withdrawn にする", async () => {
  const s = ready();
  const r = await withdraw(s, CREATOR, { packId: PACK });
  assert.deepEqual({ ...r }, { packId: PACK, status: "withdrawn", changed: true });
  assert.equal(s.packs.get(PACK)!.status, "withdrawn");
  assert.equal(s.subs.get(SID)!.status, "withdrawn");
});

test("取り下げ: 取得済みの記録とownerCountは残り、新規の取得だけが止まる", async () => {
  const s = ready();
  await acquire(s, ALICE, { packId: PACK });
  await withdraw(s, CREATOR, { packId: PACK });
  assert.equal(s.owned.has(`${ALICE}/${PACK}`), true);
  assert.equal(s.packs.get(PACK)!.ownerCount, 1);
  await rejects(acquire(s, BOB, { packId: PACK }), "failed-precondition");
});

test("取り下げ: 本人以外は permission-denied。何も変えない", async () => {
  const s = ready();
  await rejects(withdraw(s, ALICE, { packId: PACK }), "permission-denied");
  assert.equal(s.packs.get(PACK)!.status, "approved");
  assert.equal(s.subs.get(SID)!.status, "approved");
});

test("取り下げ: approved以外は failed-precondition。取り下げ済みの二重呼び出しは何も変えず成功", async () => {
  for (const st of ["suspended", "submitted"]) {
    const s = ready({ status: st });
    await rejects(withdraw(s, CREATOR, { packId: PACK }), "failed-precondition");
    assert.equal(s.packs.get(PACK)!.status, st);
  }
  const s = ready();
  await withdraw(s, CREATOR, { packId: PACK });
  const again = await withdraw(s, CREATOR, { packId: PACK });
  assert.deepEqual({ ...again }, { packId: PACK, status: "withdrawn", changed: false });
});

test("取り下げ: 無い意匠は not-found、未ログインは unauthenticated、packIdが無いときは invalid-argument", async () => {
  const s = ready();
  await rejects(withdraw(s, CREATOR, { packId: "nope" }), "not-found");
  await rejects(withdraw(s, undefined, { packId: PACK }), "unauthenticated");
  await rejects(withdraw(s, CREATOR, {}), "invalid-argument");
});

test("取り下げ: 現行版の投稿が見つからなくても、意匠は取り下げられる", async () => {
  const s = ready();
  s.subs.clear();
  assert.equal((await withdraw(s, CREATOR, { packId: PACK })).changed, true);
  assert.equal(s.packs.get(PACK)!.status, "withdrawn");
});
