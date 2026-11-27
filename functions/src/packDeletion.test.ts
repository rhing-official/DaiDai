import assert from "node:assert/strict";
import { test } from "node:test";

import {
  PACK_DELETION_MIN_NOTICE_MS,
  canTransition,
  formatJapanDateTime,
  packDeletionNoticeText,
  validateDeleteAt,
  validateDeletionText,
} from "./packDeletion";

const NOW = new Date("2026-11-17T00:00:00.000Z");

test("理由: 空白だけ・未入力は必須のとき拒否、200文字を超えると拒否", () => {
  assert.equal(validateDeletionText("  ", "理由", { required: true }).ok, false);
  assert.equal(validateDeletionText(undefined, "理由", { required: true }).ok, false);
  assert.equal(validateDeletionText(5, "理由", { required: true }).ok, false);
  assert.equal(validateDeletionText("a".repeat(201), "理由", { required: true }).ok, false);
  const ok = validateDeletionText("  誤って出品しました ", "理由", { required: true });
  assert.deepEqual(ok, { ok: true, value: "誤って出品しました" });
  assert.deepEqual(validateDeletionText("a".repeat(200), "理由", { required: true }).ok, true);
});

test("理由: 任意のときは、空でも通る", () => {
  assert.deepEqual(validateDeletionText("", "却下の理由", { required: false }), { ok: true, value: "" });
  assert.deepEqual(validateDeletionText(undefined, "却下の理由", { required: false }), { ok: true, value: "" });
});

test("削除の日時: 24時間以上先だけ通る（ちょうど24時間は通る）", () => {
  const exact = new Date(NOW.getTime() + PACK_DELETION_MIN_NOTICE_MS);
  assert.equal(validateDeleteAt(exact.toISOString(), NOW).ok, true);
  const short = new Date(NOW.getTime() + PACK_DELETION_MIN_NOTICE_MS - 1);
  assert.equal(validateDeleteAt(short.toISOString(), NOW).ok, false);
  assert.equal(validateDeleteAt(exact.getTime(), NOW).ok, true);
});

test("削除の日時: 不正な値・1年より先は拒否", () => {
  assert.equal(validateDeleteAt("あした", NOW).ok, false);
  assert.equal(validateDeleteAt(undefined, NOW).ok, false);
  const far = new Date(NOW.getTime() + 367 * 24 * 60 * 60 * 1000);
  assert.equal(validateDeleteAt(far.toISOString(), NOW).ok, false);
});

test("日時の整形: 日本時間で、分が0なら省く", () => {
  // 2026-11-24 12:00 JST = 03:00 UTC
  assert.equal(formatJapanDateTime(new Date("2026-11-24T03:00:00.000Z")), "11月24日12時");
  assert.equal(formatJapanDateTime(new Date("2026-11-24T03:30:00.000Z")), "11月24日12時30分");
  // 日付をまたぐ（UTCの15:00 = 翌日0時JST）
  assert.equal(formatJapanDateTime(new Date("2026-12-31T15:00:00.000Z")), "1月1日0時");
});

test("定型文: ぺったんの名前と日時が入る", () => {
  assert.equal(
    packDeletionNoticeText("おめでとうパック", new Date("2026-11-24T03:00:00.000Z")),
    "「おめでとうパック」というぺったんをお使いの利用者の方に連絡します。11月24日12時に使えなくなります。",
  );
});

test("状態の遷移: 申請中→承認済み/却下、承認済み→完了/取り消し/失敗", () => {
  assert.equal(canTransition("pending", "scheduled"), true);
  assert.equal(canTransition("pending", "rejected"), true);
  assert.equal(canTransition("pending", "completed"), false);
  assert.equal(canTransition("scheduled", "completed"), true);
  assert.equal(canTransition("scheduled", "cancelled"), true);
  assert.equal(canTransition("scheduled", "failed"), true);
  assert.equal(canTransition("completed", "scheduled"), false);
  assert.equal(canTransition("failed", "scheduled"), true);
  assert.equal(canTransition("rejected", "scheduled"), false);
});

import {
  deletionRequestId,
  stickerDeletionNoticeText,
  validateStickerRemoval,
} from "./packDeletion";

test("申請の文書ID: パックはpackId、1枚はpackId__stickerId", () => {
  assert.equal(deletionRequestId("p1"), "p1");
  assert.equal(deletionRequestId("p1", "s1"), "p1__s1");
});

test("1枚の削除: 下限・代表・存在しないIDを拒否する", () => {
  const ids = ["a", "b", "c", "d", "e"];
  assert.equal(validateStickerRemoval(ids, "e", "a", 4).ok, true);
  assert.equal(validateStickerRemoval(ids, "x", "a", 4).ok, false); // ない
  assert.equal(validateStickerRemoval(ids, "a", "a", 4).ok, false); // 代表
  assert.equal(validateStickerRemoval(["a", "b", "c", "d"], "d", "a", 4).ok, false); // 下限
  assert.equal(validateStickerRemoval(ids, "e", undefined, 4).ok, true);
});

test("1枚の削除のお知らせの定型文（日本時間）", () => {
  const text = stickerDeletionNoticeText("春のパック", "ねこ", new Date("2026-12-01T03:00:00.000Z"));
  assert.equal(
    text,
    "「春のパック」の中の「ねこ」をお使いの利用者の方に連絡します。12月1日12時に使えなくなります。",
  );
});

test("緊急の削除のお知らせは、日時を書かない（パック・1枚）", () => {
  const at = new Date("2026-12-01T03:00:00.000Z");
  assert.equal(
    packDeletionNoticeText("春のパック", at, true),
    "「春のパック」というぺったんをお使いの利用者の方に連絡します。緊急の対応のため、まもなく使えなくなります。",
  );
  assert.equal(
    stickerDeletionNoticeText("春のパック", "ねこ", at, true),
    "「春のパック」の中の「ねこ」をお使いの利用者の方に連絡します。緊急の対応のため、まもなく使えなくなります。",
  );
});
