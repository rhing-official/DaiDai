import assert from "node:assert/strict";
import { test } from "node:test";

import {
  SCHEDULED_FAILED_KEEP_DAYS,
  SCHEDULED_MAX_DAYS,
  isFailedScheduledExpired,
  isScheduledTimeInRange,
  scheduledSendFailure,
} from "./scheduledMessages";

const base = { conversationExists: true, roomExists: true };

test("一対: 参加者なら送れ、抜けていれば送れない", () => {
  assert.equal(
    scheduledSendFailure({
      ...base,
      scope: "dm",
      senderId: "a",
      dmParticipants: ["a", "b"],
    }),
    null,
  );
  assert.equal(
    scheduledSendFailure({
      ...base,
      scope: "dm",
      senderId: "a",
      dmParticipants: ["b"],
    }),
    "notMember",
  );
});

test("広場: 広場と寄合の両方に入っている時だけ送れる", () => {
  const ok = {
    ...base,
    scope: "group",
    senderId: "a",
    groupMemberIds: ["a"],
    roomMemberIds: ["a"],
  };
  assert.equal(scheduledSendFailure(ok), null);
  assert.equal(
    scheduledSendFailure({ ...ok, groupMemberIds: ["b"] }),
    "notMember",
  );
  assert.equal(
    scheduledSendFailure({ ...ok, roomMemberIds: ["b"] }),
    "notMember",
  );
});

test("会話・寄合が無い、または項目が不正なら送らない", () => {
  assert.equal(
    scheduledSendFailure({
      scope: "dm",
      senderId: "a",
      dmParticipants: ["a"],
      conversationExists: false,
      roomExists: true,
    }),
    "conversationMissing",
  );
  assert.equal(
    scheduledSendFailure({ ...base, scope: "x", senderId: "a" }),
    "invalid",
  );
  assert.equal(
    scheduledSendFailure({ ...base, scope: "dm", senderId: "" }),
    "invalid",
  );
});

test("予定の日時は未来から31日後まで", () => {
  const now = 1_000_000;
  const day = 24 * 60 * 60 * 1000;
  assert.equal(isScheduledTimeInRange(now, now), false);
  assert.equal(isScheduledTimeInRange(now + 1, now), true);
  assert.equal(isScheduledTimeInRange(now + SCHEDULED_MAX_DAYS * day, now), true);
  assert.equal(
    isScheduledTimeInRange(now + SCHEDULED_MAX_DAYS * day + 1, now),
    false,
  );
});

test("失敗した予定は7日たつと掃除してよい", () => {
  const day = 24 * 60 * 60 * 1000;
  assert.equal(isFailedScheduledExpired(0, SCHEDULED_FAILED_KEEP_DAYS * day - 1), false);
  assert.equal(isFailedScheduledExpired(0, SCHEDULED_FAILED_KEEP_DAYS * day), true);
});
