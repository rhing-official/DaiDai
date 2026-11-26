import assert from "node:assert/strict";
import { test } from "node:test";

import {
  ACTIVE_STATUSES,
  submitThemePack,
  SubmitError,
  type StoredFile,
  type SubmissionRecord,
  type SubmissionStore,
  type SubmissionTx,
} from "./themePackSubmit";
import { THEME_PACK_LIMITS } from "./themePack";
import { pngBytes, samplePackJson, text } from "./themePackTestBytes";

const UID = "user-a";
const SID = "11111111-2222-4333-8444-555555555555";

type Doc = SubmissionRecord & { status: string; assetPath?: string; createdAt?: number };

/** 保存先と文書を、メモリの上で再現する。transaction は、そのまま実行するだけ */
class FakeStore implements SubmissionStore {
  files = new Map<string, { bytes: Uint8Array; contentType: string }>();
  docs = new Map<string, Doc>();
  created: string[] = [];
  /** 文書の作成時刻に入れる、仮の現在時刻 */
  now = Date.now();
  blocked = new Set<string>();
  failures = new Map<string, number[]>();

  async isBlocked(uid: string) {
    return this.blocked.has(uid);
  }
  async getFailures(uid: string) {
    return this.failures.get(uid) ?? [];
  }
  async recordFailure(uid: string, nowMillis: number) {
    this.failures.set(uid, [...(this.failures.get(uid) ?? []), nowMillis]);
  }

  put(uid: string, sid: string, name: string, bytes: Uint8Array, contentType: string) {
    this.files.set(`themePackSubmissions/${uid}/${sid}/${name}`, { bytes, contentType });
  }
  putGood(uid = UID, sid = SID, packOverrides: Record<string, unknown> = {}) {
    this.put(uid, sid, "pack.json", text(samplePackJson(packOverrides)), "application/json");
    this.put(uid, sid, "background.png", pngBytes(100, 100), "image/png");
  }
  async listFiles(prefix: string): Promise<StoredFile[]> {
    return [...this.files]
      .filter(([k]) => k.startsWith(`${prefix}/`))
      .map(([k, v]) => ({ name: k.slice(prefix.length + 1), size: v.bytes.length, contentType: v.contentType }));
  }
  async readFile(prefix: string, name: string) {
    return this.files.get(`${prefix}/${name}`)!.bytes;
  }
  async runTransaction<T>(fn: (tx: SubmissionTx) => Promise<T>): Promise<T> {
    const self = this;
    return fn({
      async getSubmission(id) {
        const d = self.docs.get(id);
        return d ? { creatorId: d.creatorId, packId: d.packId, version: d.version } : null;
      },
      async countActive(creatorId) {
        return [...self.docs.values()].filter((d) => d.creatorId === creatorId && (ACTIVE_STATUSES as readonly string[]).includes(d.status)).length;
      },
      async countSince(creatorId, sinceMillis) {
        return [...self.docs.values()].filter((d) => d.creatorId === creatorId && d.createdAt !== undefined && d.createdAt >= sinceMillis).length;
      },
      async maxVersion(packId) {
        return Math.max(0, ...[...self.docs.values()].filter((d) => d.packId === packId).map((d) => d.version));
      },
      create(id, record) {
        self.docs.set(id, { ...record, status: "submitted", createdAt: self.now });
        self.created.push(id);
      },
    });
  }
}

const args = (extra: Record<string, unknown> = {}) => ({ uid: UID as string | undefined, data: { submissionId: SID, rightsAccepted: true, ...extra } });

async function rejects(p: Promise<unknown>, code: string) {
  await assert.rejects(p, (e) => e instanceof SubmitError && e.code === code);
}

test("提出: 正常なら、packId・版1で作られ、status は submitted", async () => {
  const s = new FakeStore();
  s.putGood();
  const r = await submitThemePack(s, args());
  assert.deepEqual(r, { submissionId: SID, packId: `${UID}__test-pack`, version: 1 });
  const doc = s.docs.get(SID)!;
  assert.equal(doc.status, "submitted");
  assert.equal(doc.creatorId, UID);
  assert.equal(doc.assetPath, `themePackSubmissions/${UID}/${SID}`);
  assert.equal((doc as unknown as Record<string, unknown>).name, "テスト");
  assert.equal((doc as unknown as Record<string, unknown>).brightness, "light");
});

test("提出: 未ログインは unauthenticated", async () => {
  const s = new FakeStore();
  s.putGood();
  await rejects(submitThemePack(s, { uid: undefined, data: { submissionId: SID, rightsAccepted: true } }), "unauthenticated");
});

test("提出: submissionId が UUID でない・rightsAccepted が true でないときは invalid-argument", async () => {
  const s = new FakeStore();
  s.putGood();
  await rejects(submitThemePack(s, args({ submissionId: "abc" })), "invalid-argument");
  await rejects(submitThemePack(s, args({ submissionId: "../x" })), "invalid-argument");
  await rejects(submitThemePack(s, args({ rightsAccepted: false })), "invalid-argument");
  await rejects(submitThemePack(s, args({ rightsAccepted: "true" })), "invalid-argument");
  await rejects(submitThemePack(s, { uid: UID, data: undefined }), "invalid-argument");
  assert.equal(s.docs.size, 0);
});

test("提出: ファイルが無ければ invalid-argument", async () => {
  await rejects(submitThemePack(new FakeStore(), args()), "invalid-argument");
});

test("提出: 余分なファイル・使えない contentType・検査に通らない中身は invalid-argument で、文書は作らない", async () => {
  const extra = new FakeStore();
  extra.putGood();
  extra.put(UID, SID, "extra.png", pngBytes(10, 10), "image/png");
  await rejects(submitThemePack(extra, args()), "invalid-argument");

  const badType = new FakeStore();
  badType.putGood();
  badType.put(UID, SID, "background.png", pngBytes(10, 10), "text/html");
  await rejects(submitThemePack(badType, args()), "invalid-argument");

  const fake = new FakeStore();
  fake.putGood();
  fake.put(UID, SID, "background.png", text("MZ not an image"), "image/png");
  await assert.rejects(submitThemePack(fake, args()), (e) => e instanceof SubmitError && e.code === "invalid-argument" && e.message.includes("画像として読めません"));

  const big = new FakeStore();
  big.putGood();
  big.put(UID, SID, "background.png", pngBytes(10, 10, THEME_PACK_LIMITS.imageMaxBytes), "image/png");
  await rejects(submitThemePack(big, args()), "invalid-argument");

  for (const s of [extra, badType, fake, big]) assert.equal(s.docs.size, 0);
});

test("提出: コントラスト不足は、理由つきで invalid-argument", async () => {
  const s = new FakeStore();
  s.putGood(UID, SID, { colors: { light: { text: "#FFFFFF", background: "#FFF1F5" } } });
  await assert.rejects(submitThemePack(s, args()), (e) => e instanceof SubmitError && e.message.includes("コントラスト比"));
});

test("提出: 上限5件（submitted・inReview・approved）で resource-exhausted。rejected・withdrawn は数えない", async () => {
  const s = new FakeStore();
  s.putGood();
  const statuses = ["submitted", "inReview", "approved", "rejected", "withdrawn", "suspended"];
  statuses.forEach((st, i) => s.docs.set(`d${i}`, { creatorId: UID, packId: `${UID}__p${i}`, version: 1, status: st }));
  // 数えるのは3件。あと2件までは通る
  s.docs.set("d6", { creatorId: UID, packId: `${UID}__p6`, version: 1, status: "approved" });
  s.docs.set("d7", { creatorId: UID, packId: `${UID}__p7`, version: 1, status: "approved" });
  await rejects(submitThemePack(s, args()), "resource-exhausted");
  s.docs.delete("d7");
  await submitThemePack(s, args());
  assert.ok(s.docs.has(SID));
});

test("提出: 他人の投稿は、上限に数えない", async () => {
  const s = new FakeStore();
  s.putGood();
  for (let i = 0; i < 9; i++) s.docs.set(`o${i}`, { creatorId: "other", packId: `other__p${i}`, version: 1, status: "approved" });
  await submitThemePack(s, args());
});

test("提出: 同じ packId の版は、最大 + 1。別の packId は 1 から", async () => {
  const s = new FakeStore();
  s.docs.set("old1", { creatorId: UID, packId: `${UID}__test-pack`, version: 1, status: "approved" });
  s.docs.set("old3", { creatorId: UID, packId: `${UID}__test-pack`, version: 3, status: "rejected" });
  s.docs.set("x", { creatorId: UID, packId: `${UID}__other`, version: 9, status: "withdrawn" });
  s.putGood();
  assert.equal((await submitThemePack(s, args())).version, 4);

  const s2 = new FakeStore();
  s2.putGood(UID, SID, { id: "second" });
  assert.deepEqual(await submitThemePack(s2, args()), { submissionId: SID, packId: `${UID}__second`, version: 1 });
});

test("提出: 他人の投稿者が同じ id を使っても、packId は別（投稿者ごとの名前空間）", async () => {
  const s = new FakeStore();
  s.docs.set("b", { creatorId: "user-b", packId: "user-b__test-pack", version: 5, status: "approved" });
  s.putGood();
  assert.equal((await submitThemePack(s, args())).version, 1);
});

test("提出: 他人の submissionId は permission-denied（文書は変えない）", async () => {
  const s = new FakeStore();
  s.docs.set(SID, { creatorId: "user-b", packId: "user-b__test-pack", version: 1, status: "submitted" });
  s.putGood();
  await rejects(submitThemePack(s, args()), "permission-denied");
  assert.equal(s.docs.get(SID)!.creatorId, "user-b");
  assert.equal(s.created.length, 0);
});

test("提出: 他人の保存先は読まない（呼び出し元の uid の保存先だけを見る）", async () => {
  const s = new FakeStore();
  s.putGood("user-b", SID); // 他人の保存先にだけ、ファイルが有る
  await rejects(submitThemePack(s, args()), "invalid-argument");
  assert.equal(s.docs.size, 0);
});

test("提出: 同じ submissionId の再送は、二重に作らず、同じ結果を返す（上限でも）", async () => {
  const s = new FakeStore();
  s.putGood();
  const first = await submitThemePack(s, args());
  // 上限まで増やしても、作成済みの再送は成功する
  for (let i = 0; i < 4; i++) s.docs.set(`d${i}`, { creatorId: UID, packId: `${UID}__p${i}`, version: 1, status: "approved" });
  const again = await submitThemePack(s, args());
  assert.deepEqual(again, first);
  assert.deepEqual(s.created, [SID]);
});

const HOUR = 60 * 60 * 1000;
const T0 = 1_800_000_000_000;

/** 時刻を固定して提出する。別の submissionId を使い、毎回新しい提出にする */
function submitAt(s: FakeStore, t: number, n: number) {
  s.now = t;
  const sid = `11111111-2222-4333-8444-${String(n).padStart(12, "0")}`;
  s.putGood(UID, sid);
  return submitThemePack(s, { uid: UID, data: { submissionId: sid, rightsAccepted: true }, now: t });
}

test("1日の上限: 24時間に5回まで通り、6回目は resource-exhausted。却下された物も数える", async () => {
  const s = new FakeStore();
  for (let i = 1; i <= 5; i++) {
    await submitAt(s, T0 + i * 1000, i);
    // 公開中・審査中の上限（5件）に当たらないよう、状態を却下へ変える
    for (const d of s.docs.values()) d.status = "rejected";
  }
  await assert.rejects(submitAt(s, T0 + 10_000, 6), (e) => e instanceof SubmitError && e.code === "resource-exhausted" && e.message.includes("24時間"));
  assert.equal(s.docs.size, 5);
});

test("1日の上限: 24時間が過ぎると、また出せる。他人の投稿は数えない", async () => {
  const s = new FakeStore();
  for (let i = 1; i <= 5; i++) {
    await submitAt(s, T0, i);
    for (const d of s.docs.values()) d.status = "rejected";
  }
  await submitAt(s, T0 + 24 * HOUR + 1, 6);
  const other = new FakeStore();
  for (let i = 0; i < 9; i++) other.docs.set(`o${i}`, { creatorId: "other", packId: `other__p${i}`, version: 1, status: "rejected", createdAt: T0 });
  await submitAt(other, T0, 1);
});

test("1日の上限: 作成済みの submissionId の再送は、上限でも通る", async () => {
  const s = new FakeStore();
  const first = await submitAt(s, T0, 1);
  for (let i = 2; i <= 5; i++) s.docs.set(`x${i}`, { creatorId: UID, packId: `${UID}__x${i}`, version: 1, status: "rejected", createdAt: T0 });
  const again = await submitThemePack(s, { uid: UID, data: { submissionId: first.submissionId, rightsAccepted: true }, now: T0 + 1000 });
  assert.deepEqual(again, first);
});

test("失敗の回数: 検査に落ちる度に記録し、10回で1時間止まる。止めている間は回数に足さない", async () => {
  const s = new FakeStore(); // 素材を置かない＝毎回 invalid-argument
  const sid = (n: number) => `11111111-2222-4333-8444-${String(n).padStart(12, "0")}`;
  const call = (n: number, t: number) => submitThemePack(s, { uid: UID, data: { submissionId: sid(n), rightsAccepted: true }, now: t });
  for (let i = 0; i < 9; i++) await rejects(call(i, T0 + i * 1000), "invalid-argument");
  assert.equal(s.failures.get(UID)!.length, 9);
  await rejects(call(9, T0 + 9000), "invalid-argument"); // 10回目も、検査の失敗として扱う
  assert.equal(s.failures.get(UID)!.length, 10);
  await assert.rejects(call(10, T0 + 10_000), (e) => e instanceof SubmitError && e.code === "resource-exhausted" && e.message.includes("失敗が続いた"));
  assert.equal(s.failures.get(UID)!.length, 10); // 止めている間は足さない
  // 最後の失敗（T0+9000）から1時間後に解除される。その時は、検査に進む
  await rejects(call(11, T0 + 9000 + HOUR - 1), "resource-exhausted");
  await rejects(call(12, T0 + 9000 + HOUR), "invalid-argument");
});

test("失敗の回数: 1時間より古い失敗は数えない", async () => {
  const s = new FakeStore();
  s.failures.set(UID, Array.from({ length: 10 }, (_, i) => T0 + i));
  s.putGood();
  // 10回は2時間前。停止は、最後の失敗から1時間で終わっている
  await submitThemePack(s, { uid: UID, data: { submissionId: SID, rightsAccepted: true }, now: T0 + 2 * HOUR });
  assert.ok(s.docs.has(SID));
});

test("運営の停止: 停止中は permission-denied。再送も受け付けず、解除すれば通る", async () => {
  const s = new FakeStore();
  s.putGood();
  s.blocked.add(UID);
  await rejects(submitThemePack(s, args()), "permission-denied");
  assert.equal(s.docs.size, 0);
  s.blocked.delete(UID);
  await submitThemePack(s, args());
  s.blocked.add(UID);
  await rejects(submitThemePack(s, args()), "permission-denied"); // 作成済みの再送も止める
  const other = new FakeStore();
  other.putGood("user-b", SID);
  other.blocked.add(UID); // 他人の停止は、関係しない
  await submitThemePack(other, { uid: "user-b", data: { submissionId: SID, rightsAccepted: true } });
});
