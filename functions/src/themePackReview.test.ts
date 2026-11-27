import assert from "node:assert/strict";
import { test } from "node:test";

import {
  MAX_REASON_LENGTH,
  NOTICE_KINDS,
  ReviewError,
  approveThemePack,
  approvedNoticeText,
  rejectThemePack,
  rejectedNoticeText,
  suspendThemePack,
  suspendedCreatorNoticeText,
  suspendedOwnerNoticeText,
  type Notice,
  type PublicPack,
  type PublicPackData,
  type ReviewStore,
  type ReviewSubmission,
  type ReviewTx,
  type StoredFile,
} from "./themePackReview";
import { pngBytes, samplePackJson, text } from "./themePackTestBytes";

const CREATOR = "creator-a";
const ADMIN = "admin-1";
const SID = "11111111-2222-4333-8444-555555555555";
const SID2 = "11111111-2222-4333-8444-666666666666";
const PACK = `${CREATOR}__test-pack`;

type PubDoc = PublicPack & { assetPath: string; brightness: string; ownerCount: number; price: number; createdAt: boolean };

class FakeReviewStore implements ReviewStore {
  files = new Map<string, Uint8Array>();
  subs = new Map<string, ReviewSubmission & Record<string, unknown>>();
  packs = new Map<string, PubDoc>();
  notices: { uid: string; notice: Notice }[] = [];
  owners: string[] = [];
  batchSizes: number[] = [];
  copies: string[] = [];

  putFiles(sid: string, packOverrides: Record<string, unknown> = {}, creator = CREATOR) {
    const prefix = `themePackSubmissions/${creator}/${sid}`;
    this.files.set(`${prefix}/pack.json`, text(samplePackJson(packOverrides)));
    this.files.set(`${prefix}/background.png`, pngBytes(100, 100));
  }
  putSub(sid: string, version: number, over: Partial<ReviewSubmission> & Record<string, unknown> = {}) {
    this.subs.set(sid, {
      creatorId: CREATOR,
      packId: PACK,
      version,
      status: "submitted",
      assetPath: `themePackSubmissions/${CREATOR}/${sid}`,
      name: "テスト",
      ...over,
    });
  }
  async listFiles(prefix: string): Promise<StoredFile[]> {
    return [...this.files]
      .filter(([k]) => k.startsWith(`${prefix}/`))
      .map(([k, v]) => ({ name: k.slice(prefix.length + 1), size: v.length, contentType: undefined }));
  }
  async readFile(prefix: string, name: string) {
    const f = this.files.get(`${prefix}/${name}`);
    if (!f) throw new Error("not found");
    return f;
  }
  async copyFile(from: string, to: string, name: string) {
    this.files.set(`${to}/${name}`, this.files.get(`${from}/${name}`)!);
    this.copies.push(`${to}/${name}`);
  }
  async runTransaction<T>(fn: (tx: ReviewTx) => Promise<T>): Promise<T> {
    const self = this;
    return fn({
      async getSubmission(id) {
        const s = self.subs.get(id);
        return s ? { ...s } : null;
      },
      async getPublicPack(packId) {
        const p = self.packs.get(packId);
        return p ? { creatorId: p.creatorId, name: p.name, version: p.version, status: p.status } : null;
      },
      async findSubmission(packId, version) {
        for (const [id, s] of self.subs) if (s.packId === packId && s.version === version) return { id, status: s.status };
        return null;
      },
      updateSubmission(id, patch) {
        Object.assign(self.subs.get(id)!, patch, patch.status !== undefined ? { decidedAt: true } : {});
      },
      createPublicPack(packId, d: PublicPackData) {
        self.packs.set(packId, { ...d, status: "approved", ownerCount: 0, price: 0, createdAt: true });
      },
      updatePublicPack(packId, d: PublicPackData) {
        Object.assign(self.packs.get(packId)!, d, { status: "approved" });
      },
      suspendPublicPack(packId) {
        self.packs.get(packId)!.status = "suspended";
      },
      addNotice(uid, notice) {
        self.notices.push({ uid, notice });
      },
    });
  }
  async listOwnerUids() {
    return this.owners;
  }
  async writeNoticeBatch(uids: string[], notice: Notice) {
    this.batchSizes.push(uids.length);
    for (const uid of uids) this.notices.push({ uid, notice });
  }
}

const approve = (s: FakeReviewStore, sid = SID) => approveThemePack(s, { adminUid: ADMIN, data: { submissionId: sid } });
const reject = (s: FakeReviewStore, data: unknown) => rejectThemePack(s, { adminUid: ADMIN, data });
const suspend = (s: FakeReviewStore, data: unknown) => suspendThemePack(s, { adminUid: ADMIN, data });

async function rejects(p: Promise<unknown>, code: string) {
  await assert.rejects(p, (e) => e instanceof ReviewError && e.code === code);
}

function ready(): FakeReviewStore {
  const s = new FakeReviewStore();
  s.putFiles(SID);
  s.putSub(SID, 1);
  return s;
}

test("承認: 素材を公開側へコピーし、themePacksを作り、投稿を承認し、出品者へお知らせを1件書く", async () => {
  const s = ready();
  const r = await approve(s);
  assert.deepEqual(
    { ...r },
    { submissionId: SID, packId: PACK, creatorId: CREATOR, version: 1, status: "approved", changed: true },
  );
  assert.deepEqual(s.copies.sort(), [`themePacks/${PACK}/1/background.png`, `themePacks/${PACK}/1/pack.json`]);
  // 投稿の場所は残る
  assert.ok(s.files.has(`themePackSubmissions/${CREATOR}/${SID}/pack.json`));
  const pub = s.packs.get(PACK)!;
  assert.equal(pub.status, "approved");
  assert.equal(pub.assetPath, `themePacks/${PACK}/1`);
  assert.equal(pub.ownerCount, 0);
  assert.equal(pub.price, 0);
  assert.equal(pub.version, 1);
  assert.equal(pub.creatorId, CREATOR);
  assert.equal(pub.name, "テスト");
  assert.equal(s.subs.get(SID)!.status, "approved");
  assert.equal(s.subs.get(SID)!.decidedBy, ADMIN);
  assert.equal(s.subs.get(SID)!.decidedAt, true);
  assert.equal(s.notices.length, 1);
  assert.deepEqual(s.notices[0], {
    uid: CREATOR,
    notice: { kind: "themePackApproved", packId: PACK, content: "意匠『テスト』が承認され、公開されました。" },
  });
});

test("承認: 二重の呼び出しは、結果を変えず、お知らせも重ねない", async () => {
  const s = ready();
  await approve(s);
  const second = await approve(s);
  assert.equal(second.changed, false);
  assert.equal(second.status, "approved");
  assert.equal(s.notices.length, 1);
});

test("承認: inReviewからも承認できる。他の状態は failed-precondition", async () => {
  const s = ready();
  s.subs.get(SID)!.status = "inReview";
  await approve(s);
  for (const st of ["rejected", "withdrawn", "suspended"]) {
    const t = ready();
    t.subs.get(SID)!.status = st;
    await rejects(approve(t), "failed-precondition");
    assert.equal(t.packs.size, 0);
    assert.equal(t.copies.length, 0);
  }
});

test("承認: 投稿が無い、submissionIdが無いときの拒否", async () => {
  const s = ready();
  await rejects(approve(s, SID2), "not-found");
  await rejects(approveThemePack(s, { adminUid: ADMIN, data: {} }), "invalid-argument");
});

test("承認: 再検査に通らなければ、承認もコピーもしない", async () => {
  const s = ready();
  // 背景画像が無い
  s.files.delete(`themePackSubmissions/${CREATOR}/${SID}/background.png`);
  await rejects(approve(s), "failed-precondition");
  assert.equal(s.subs.get(SID)!.status, "submitted");
  assert.equal(s.packs.size, 0);
  assert.equal(s.copies.length, 0);
  assert.equal(s.notices.length, 0);

  // 実行できる形式のファイルが混ざっている
  const t = ready();
  t.files.set(`themePackSubmissions/${CREATOR}/${SID}/evil.js`, text("alert(1)"));
  await rejects(approve(t), "failed-precondition");
  assert.equal(t.packs.size, 0);
});

test("承認: 素材のidが投稿の記録と食い違えば拒否", async () => {
  const s = new FakeReviewStore();
  s.putFiles(SID, { id: "other-pack" });
  s.putSub(SID, 1);
  await rejects(approve(s), "failed-precondition");
});

test("版の更新: 旧版を公開したまま、新しい版を承認すると差し替わる。作成日と所有数は変わらない", async () => {
  const s = ready();
  await approve(s);
  s.packs.get(PACK)!.ownerCount = 7;
  // 新しい版は、承認されるまで旧版が公開のまま
  s.putFiles(SID2, { name: "テスト2" });
  s.putSub(SID2, 2, { name: "テスト2" });
  assert.equal(s.packs.get(PACK)!.version, 1);
  assert.equal(s.packs.get(PACK)!.status, "approved");

  await approve(s, SID2);
  const pub = s.packs.get(PACK)!;
  assert.equal(pub.version, 2);
  assert.equal(pub.name, "テスト2");
  assert.equal(pub.assetPath, `themePacks/${PACK}/2`);
  assert.equal(pub.ownerCount, 7);
  assert.ok(s.files.has(`themePacks/${PACK}/1/pack.json`), "旧版の素材は残る");
  assert.ok(s.files.has(`themePacks/${PACK}/2/pack.json`));
});

test("承認: 公開中より古い版、配信停止中の意匠への新版は拒否", async () => {
  const s = ready();
  s.putFiles(SID2);
  s.putSub(SID2, 2);
  await approve(s, SID2);
  await rejects(approve(s, SID), "failed-precondition");
  assert.equal(s.packs.get(PACK)!.version, 2);

  await suspend(s, { packId: PACK, reason: "権利" });
  const SID3 = "11111111-2222-4333-8444-777777777777";
  s.putFiles(SID3);
  s.putSub(SID3, 3);
  await rejects(approve(s, SID3), "failed-precondition");
  assert.equal(s.packs.get(PACK)!.status, "suspended");
});

test("差し戻し: 理由が必須で、空・空白のみ・501文字は拒否", async () => {
  const s = ready();
  await rejects(reject(s, { submissionId: SID }), "invalid-argument");
  await rejects(reject(s, { submissionId: SID, reason: "   " }), "invalid-argument");
  await rejects(reject(s, { submissionId: SID, reason: "あ".repeat(MAX_REASON_LENGTH + 1) }), "invalid-argument");
  await rejects(reject(s, { submissionId: SID, reason: 123 }), "invalid-argument");
  assert.equal(s.subs.get(SID)!.status, "submitted");
  assert.equal(s.notices.length, 0);
  // 500文字ちょうどは通る
  await reject(s, { submissionId: SID, reason: "あ".repeat(MAX_REASON_LENGTH) });
  assert.equal(s.subs.get(SID)!.status, "rejected");
});

test("差し戻し: 状態・記録・お知らせ。名前が無い古い投稿は、pack.json から補う", async () => {
  const s = new FakeReviewStore();
  s.putFiles(SID, { name: "桜" });
  s.putSub(SID, 1, { name: undefined });
  await reject(s, { submissionId: SID, reason: "  色が読みにくいです。  " });
  const sub = s.subs.get(SID)!;
  assert.equal(sub.status, "rejected");
  assert.equal(sub.decisionNote, "色が読みにくいです。");
  assert.equal(sub.decidedBy, ADMIN);
  assert.equal(sub.decidedAt, true);
  assert.deepEqual(s.notices, [
    {
      uid: CREATOR,
      notice: {
        kind: "themePackRejected",
        packId: PACK,
        content: "意匠『桜』は、差し戻されました。理由は次のとおりです。\n色が読みにくいです。",
      },
    },
  ]);
  assert.equal(s.packs.size, 0, "差し戻しは公開側に触れない");
});

test("差し戻し: submitted/inReview 以外と、存在しない投稿は拒否", async () => {
  const s = ready();
  await approve(s);
  await rejects(reject(s, { submissionId: SID, reason: "x" }), "failed-precondition");
  await rejects(reject(s, { submissionId: SID2, reason: "x" }), "not-found");
});

test("配信停止: 取り下げ済み（withdrawn）の意匠も停止でき、現行版の投稿はsuspendedになる", async () => {
  const s = ready();
  await approve(s);
  s.packs.get(PACK)!.status = "withdrawn";
  s.subs.get(SID)!.status = "withdrawn";
  const r = await suspend(s, { packId: PACK, reason: "権利の侵害" });
  assert.equal(r.status, "suspended");
  assert.equal(r.changed, true);
  assert.equal(s.packs.get(PACK)!.status, "suspended");
  assert.equal(s.subs.get(SID)!.status, "suspended");
});

test("配信停止: 取得者0件でも動き、themePacksと投稿を停止し、出品者へ理由つきで知らせる。素材は残す", async () => {
  const s = ready();
  await approve(s);
  s.notices.length = 0;
  const r = await suspend(s, { packId: PACK, reason: " 権利の侵害 " });
  assert.deepEqual({ ...r }, { packId: PACK, creatorId: CREATOR, status: "suspended", notifiedOwners: 0, changed: true });
  assert.equal(s.packs.get(PACK)!.status, "suspended");
  assert.equal(s.subs.get(SID)!.status, "suspended");
  assert.equal(s.subs.get(SID)!.decisionNote, "権利の侵害");
  assert.ok(s.files.has(`themePacks/${PACK}/1/pack.json`));
  assert.deepEqual(s.batchSizes, []);
  assert.equal(s.notices.length, 1);
  assert.equal(s.notices[0].uid, CREATOR);
  assert.equal(s.notices[0].notice.content, "意匠『テスト』の配信を停止しました。理由は次のとおりです。\n権利の侵害");
});

test("配信停止: 取得者への書き込みは400件ずつ（401件 → 400と1）。理由は出さない", async () => {
  const s = ready();
  await approve(s);
  s.owners = Array.from({ length: 401 }, (_, i) => `owner-${i}`);
  const r = await suspend(s, { packId: PACK, reason: "秘密の理由" });
  assert.equal(r.notifiedOwners, 401);
  assert.deepEqual(s.batchSizes, [400, 1]);
  const ownerNotices = s.notices.filter((n) => n.uid.startsWith("owner-"));
  assert.equal(ownerNotices.length, 401);
  for (const n of ownerNotices) {
    assert.equal(n.notice.kind, "themePackSuspended");
    assert.equal(n.notice.content, "取得した意匠『テスト』の配信が停止されました。表示は標準に戻ります。");
    assert.ok(!n.notice.content.includes("秘密の理由"));
  }
  // ちょうど400件は1回
  const t = ready();
  await approve(t);
  t.owners = Array.from({ length: 400 }, (_, i) => `o${i}`);
  await suspend(t, { packId: PACK, reason: "x" });
  assert.deepEqual(t.batchSizes, [400]);
});

test("配信停止: 停止済みの再実行は状態を変えず、取得者のお知らせは同じ文書IDで書き直す", async () => {
  const s = ready();
  await approve(s);
  s.owners = ["o1"];
  await suspend(s, { packId: PACK, reason: "x" });
  const creatorNotices = s.notices.filter((n) => n.uid === CREATOR).length;
  const again = await suspend(s, { packId: PACK, reason: "x" });
  assert.equal(again.changed, false);
  assert.equal(s.notices.filter((n) => n.uid === CREATOR).length, creatorNotices, "出品者へは重ねない");
  const ownerNotices = s.notices.filter((n) => n.uid === "o1");
  assert.equal(ownerNotices.length, 2);
  assert.equal(ownerNotices[0].notice.id, ownerNotices[1].notice.id);
  assert.ok(ownerNotices[0].notice.id);
});

test("配信停止: 理由の検査と、存在しない意匠", async () => {
  const s = ready();
  await approve(s);
  await rejects(suspend(s, { packId: PACK }), "invalid-argument");
  await rejects(suspend(s, { packId: PACK, reason: "あ".repeat(501) }), "invalid-argument");
  await rejects(suspend(s, { reason: "x" }), "invalid-argument");
  await rejects(suspend(s, { packId: "nope", reason: "x" }), "not-found");
  assert.equal(s.packs.get(PACK)!.status, "approved");
});

test("お知らせの文面と kind", () => {
  assert.equal(approvedNoticeText("桜"), "意匠『桜』が承認され、公開されました。");
  assert.equal(rejectedNoticeText("桜", "理由"), "意匠『桜』は、差し戻されました。理由は次のとおりです。\n理由");
  assert.equal(suspendedCreatorNoticeText("桜", "理由"), "意匠『桜』の配信を停止しました。理由は次のとおりです。\n理由");
  assert.equal(suspendedOwnerNoticeText("桜"), "取得した意匠『桜』の配信が停止されました。表示は標準に戻ります。");
  assert.deepEqual({ ...NOTICE_KINDS }, {
    approved: "themePackApproved",
    rejected: "themePackRejected",
    suspended: "themePackSuspended",
  });
});
