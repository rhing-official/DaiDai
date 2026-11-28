import assert from "node:assert/strict";
import { test } from "node:test";

import {
  FREE_RETENTION_DAYS,
  KIWAMI_RETENTION_DAYS,
  attachmentStoragePaths,
  conversationFromDocPath,
  deleteMessageAttachments,
  expireMessageAttachments,
  hasExpirableAttachment,
  legacyExpiresAtMs,
  retentionExpiresAtMs,
  type RetentionStore,
} from "./retention";

const DAY = 24 * 60 * 60 * 1000;
const T = 1_800_000_000_000;

test("無料は30日、極みは180日", () => {
  assert.equal(FREE_RETENTION_DAYS, 30);
  assert.equal(KIWAMI_RETENTION_DAYS, 180);
  assert.equal(retentionExpiresAtMs(T, false), T + 30 * DAY);
  assert.equal(retentionExpiresAtMs(T, true), T + 180 * DAY);
});

test("既存のメッセージは、予告の日から30日より前にならない", () => {
  const notice = T;
  // 100日前に送った無料の人の画像: 通常なら期限は70日前だが、予告から30日。
  assert.equal(legacyExpiresAtMs(T - 100 * DAY, false, notice), T + 30 * DAY);
  // 極みで10日前: 通常の期限（170日後）が、予告から30日より後。
  assert.equal(legacyExpiresAtMs(T - 10 * DAY, true, notice), T + 170 * DAY);
});

test("文書のパスから会話を取り出す。チャット以外はnull", () => {
  assert.deepEqual(conversationFromDocPath("directMessages/d1/rooms/r1/messages/m1"), {
    kind: "dm",
    id: "d1",
    messageId: "m1",
  });
  assert.deepEqual(conversationFromDocPath("groups/g1/rooms/r1/messages/m1"), {
    kind: "group",
    id: "g1",
    messageId: "m1",
  });
  assert.equal(conversationFromDocPath("users/u1/notices/n1"), null);
  assert.equal(conversationFromDocPath("groups/g1/rooms/r1/messages/m1/x/y"), null);
});

test("添付の有無: ぺったん・文字だけは対象外", () => {
  assert.equal(hasExpirableAttachment({ fileMetadata: { extension: "webp" } }), true);
  assert.equal(hasExpirableAttachment({ attachments: [{ extension: "mp4" }] }), true);
  assert.equal(hasExpirableAttachment({ fileMetadata: null, attachments: [] }), false);
  assert.equal(hasExpirableAttachment({}), false);
  assert.equal(hasExpirableAttachment(undefined), false);
});

test("単一の添付: 本体・サムネイル・再生用を挙げる", () => {
  const paths = attachmentStoragePaths(
    { fileMetadata: { extension: "mp4", playbackPath: "dmFiles/d1/m1_play.mp4" } },
    { kind: "dm", id: "d1", messageId: "m1" },
  );
  assert.deepEqual(paths.sort(), [
    "dmFiles/d1/m1.mp4",
    "dmFiles/d1/m1_play.mp4",
    "dmFiles/d1/m1_thumb.jpg",
  ]);
});

test("広場の複数添付: 添付ごとに3種を挙げる。先頭のドットは外す", () => {
  const paths = attachmentStoragePaths(
    { attachments: [{ extension: ".webp" }, { extension: "pdf" }], fileMetadata: { extension: "webp" } },
    { kind: "group", id: "g1", messageId: "m9" },
  );
  assert.ok(paths.includes("groupFiles/g1/m9/0.webp"));
  assert.ok(paths.includes("groupFiles/g1/m9/1.pdf"));
  assert.ok(paths.includes("groupFiles/g1/m9/1_thumb.jpg"));
  assert.ok(paths.includes("groupFiles/g1/m9/0_play.mp4"));
  // 複数添付の時は、単一のパス（m9.webp）を挙げない。
  assert.ok(!paths.includes("groupFiles/g1/m9.webp"));
  assert.equal(new Set(paths).size, paths.length);
});

test("アルバムのパスは挙げない", () => {
  const paths = attachmentStoragePaths(
    { fileMetadata: { extension: "webp" } },
    { kind: "dm", id: "d1", messageId: "m1" },
  );
  assert.ok(paths.every((p) => p.startsWith("dmFiles/")));
});

function fakeStore(failOn: string[] = []): RetentionStore & {
  deleted: string[];
  marked: string[];
} {
  const deleted: string[] = [];
  const marked: string[] = [];
  return {
    deleted,
    marked,
    async deleteFile(path) {
      if (failOn.includes(path)) throw new Error("boom");
      deleted.push(path);
    },
    async markExpired(docPath) {
      marked.push(docPath);
    },
  };
}

const MSG = "directMessages/d1/rooms/r1/messages/m1";
const IMG = { fileMetadata: { extension: "webp" } };

test("有効でない時は、何も消さず、件数だけ数える", async () => {
  const store = fakeStore();
  const r = await expireMessageAttachments(store, [{ docPath: MSG, data: IMG }], false);
  assert.equal(r.dryRun, true);
  assert.equal(r.wouldExpire, 1);
  assert.deepEqual(store.deleted, []);
  assert.deepEqual(store.marked, []);
});

test("有効な時は、添付を消して、印を付ける", async () => {
  const store = fakeStore();
  const r = await expireMessageAttachments(store, [{ docPath: MSG, data: IMG }], true);
  assert.deepEqual(r.expired, [MSG]);
  assert.deepEqual(store.marked, [MSG]);
  assert.ok(store.deleted.includes("dmFiles/d1/m1.webp"));
});

test("1件でも消せなければ、印を付けず、他のメッセージは続ける", async () => {
  const store = fakeStore(["dmFiles/d1/m1.webp"]);
  const other = "groups/g1/rooms/r1/messages/m2";
  const r = await expireMessageAttachments(
    store,
    [
      { docPath: MSG, data: IMG },
      { docPath: other, data: IMG },
    ],
    true,
  );
  assert.deepEqual(r.failed, [MSG]);
  assert.deepEqual(r.expired, [other]);
  assert.deepEqual(store.marked, [other]);
});

test("上限を超える分は残す。添付の無いメッセージは数えない", async () => {
  const store = fakeStore();
  const msgs = [
    { docPath: "directMessages/d1/rooms/r1/messages/a", data: IMG },
    { docPath: "directMessages/d1/rooms/r1/messages/b", data: {} },
    { docPath: "directMessages/d1/rooms/r1/messages/c", data: IMG },
    { docPath: "directMessages/d1/rooms/r1/messages/d", data: IMG },
  ];
  const r = await expireMessageAttachments(store, msgs, true, 2);
  assert.equal(r.expired.length, 2);
  assert.ok(!r.expired.includes("directMessages/d1/rooms/r1/messages/b"));
});

test("送信取消の削除: 消せたものと失敗したものを分ける", async () => {
  const store = fakeStore(["dmFiles/d1/m1_thumb.jpg"]);
  const r = await deleteMessageAttachments(store, MSG, IMG);
  assert.deepEqual(r.failed, ["dmFiles/d1/m1_thumb.jpg"]);
  assert.ok(r.deleted.includes("dmFiles/d1/m1.webp"));
});

test("チャット以外のパスでは、何も消さない", async () => {
  const store = fakeStore();
  const r = await deleteMessageAttachments(store, "users/u1/x", IMG);
  assert.deepEqual(r, { deleted: [], failed: [] });
});
