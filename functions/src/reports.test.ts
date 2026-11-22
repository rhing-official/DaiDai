import assert from "node:assert/strict";
import { test } from "node:test";

import {
  REPORT_DAILY_LIMIT,
  REPORT_NOTE_MAX_LENGTH,
  isOverDailyLimit,
  parseReportInput,
  parseResolution,
  reportTargetKey,
  toEvidenceMessage,
} from "./reports";

test("通報の入力: メッセージ（一対）を受け付ける", () => {
  const r = parseReportInput({
    targetType: "message",
    reason: "harassment",
    note: "  ひどい  ",
    dmId: "dm1",
    roomId: "r1",
    messageId: "m1",
  });
  assert.equal(r.ok, true);
  if (!r.ok) return;
  assert.equal(r.input.note, "ひどい");
  assert.equal(r.input.dmId, "dm1");
  assert.equal(r.input.groupId, undefined);
});

test("通報の入力: メッセージはdmIdとgroupIdのどちらか一方だけ", () => {
  const base = { targetType: "message", reason: "spam", roomId: "r", messageId: "m" };
  assert.equal(parseReportInput({ ...base }).ok, false);
  assert.equal(parseReportInput({ ...base, dmId: "a", groupId: "b" }).ok, false);
  assert.equal(parseReportInput({ ...base, groupId: "g" }).ok, true);
});

test("通報の入力: 住人・広場", () => {
  assert.equal(
    parseReportInput({ targetType: "user", reason: "other", targetUserId: "u" }).ok,
    true,
  );
  assert.equal(parseReportInput({ targetType: "user", reason: "other" }).ok, false);
  assert.equal(
    parseReportInput({ targetType: "group", reason: "illegal", groupId: "g" }).ok,
    true,
  );
  assert.equal(parseReportInput({ targetType: "group", reason: "illegal" }).ok, false);
});

test("通報の入力: 不正な種類・理由・長すぎる補足・idの「/」を拒否する", () => {
  assert.equal(parseReportInput({ targetType: "x", reason: "spam" }).ok, false);
  assert.equal(
    parseReportInput({ targetType: "user", reason: "x", targetUserId: "u" }).ok,
    false,
  );
  assert.equal(
    parseReportInput({
      targetType: "user",
      reason: "spam",
      targetUserId: "u",
      note: "あ".repeat(REPORT_NOTE_MAX_LENGTH + 1),
    }).ok,
    false,
  );
  assert.equal(
    parseReportInput({ targetType: "user", reason: "spam", targetUserId: "a/b" }).ok,
    false,
  );
  assert.equal(parseReportInput(null).ok, false);
});

test("通報の対象のキー: 対象ごとに異なり、同じ対象なら同じ", () => {
  const a = parseReportInput({
    targetType: "message",
    reason: "spam",
    dmId: "d",
    roomId: "r",
    messageId: "m1",
  });
  const b = parseReportInput({
    targetType: "message",
    reason: "harassment",
    dmId: "d",
    roomId: "r",
    messageId: "m1",
  });
  const c = parseReportInput({
    targetType: "message",
    reason: "spam",
    dmId: "d",
    roomId: "r",
    messageId: "m2",
  });
  assert.ok(a.ok && b.ok && c.ok);
  if (!(a.ok && b.ok && c.ok)) return;
  assert.equal(reportTargetKey(a.input), reportTargetKey(b.input));
  assert.notEqual(reportTargetKey(a.input), reportTargetKey(c.input));
});

test("証拠: メッセージを複写し、長い本文は切り詰め、添付を写す", () => {
  const e = toEvidenceMessage(
    "m1",
    {
      senderId: "u1",
      senderRhingSeed: "alice",
      content: "あ".repeat(3000),
      contentType: "image",
      sentAt: { toDate: () => new Date("2026-11-22T00:00:00.000Z") },
      fileMetadata: { url: "https://x/y.webp", fileName: "y.webp", mimeType: "image/webp", sizeBytes: 10 },
    },
    true,
  );
  assert.equal(e.content.length, 2000);
  assert.equal(e.sentAt, "2026-11-22T00:00:00.000Z");
  assert.equal(e.isTarget, true);
  assert.equal(e.attachments.length, 1);
  assert.equal(e.attachments[0].fileName, "y.webp");
});

test("証拠: 欠けた項目は既定値にする", () => {
  const e = toEvidenceMessage("m", {}, false);
  assert.equal(e.senderId, "");
  assert.equal(e.senderRhingSeed, null);
  assert.equal(e.sentAt, null);
  assert.deepEqual(e.attachments, []);
});

test("1日の上限: 24時間以内の件数だけ数える", () => {
  const now = Date.UTC(2026, 10, 22);
  const recent = Array.from({ length: REPORT_DAILY_LIMIT - 1 }, () => now - 1000);
  assert.equal(isOverDailyLimit(recent, now), false);
  assert.equal(isOverDailyLimit([...recent, now - 2000], now), true);
  const old = Array.from({ length: REPORT_DAILY_LIMIT }, () => now - 25 * 3600 * 1000);
  assert.equal(isOverDailyLimit(old, now), false);
});

test("運営の処理: 却下・対応済みだけ受け付ける", () => {
  assert.equal(parseResolution({ resolution: "dismissed" }).ok, true);
  assert.equal(parseResolution({ resolution: "actioned", note: " メモ " }).ok, true);
  assert.equal(parseResolution({ resolution: "deleted" }).ok, false);
  assert.equal(parseResolution({}).ok, false);
});
