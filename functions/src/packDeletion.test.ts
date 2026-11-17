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
