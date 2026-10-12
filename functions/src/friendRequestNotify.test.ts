import assert from "node:assert/strict";
import { test } from "node:test";

import {
  FRIEND_REQUEST_BODY,
  friendRequestBody,
  resolveFriendRequestRecipient,
} from "./friendRequestNotify";

const pending = { status: "pending", fromUserId: "a", toUserId: "b" };

test("新規の申請は宛先（受ける側）と送信者を返す", () => {
  assert.deepEqual(resolveFriendRequestRecipient(undefined, pending), {
    recipientId: "b",
    senderId: "a",
  });
});

test("却下後の再申請（declined→pending）も通知する", () => {
  assert.ok(
    resolveFriendRequestRecipient({ ...pending, status: "declined" }, pending),
  );
});

test("承認・取り消し・変化なし（pending→pending）・削除では通知しない", () => {
  assert.equal(resolveFriendRequestRecipient(pending, pending), null);
  assert.equal(
    resolveFriendRequestRecipient(pending, { ...pending, status: "accepted" }),
    null,
  );
  assert.equal(resolveFriendRequestRecipient(pending, undefined), null);
});

test("不正な値・自分宛ては通知しない", () => {
  assert.equal(
    resolveFriendRequestRecipient(undefined, { status: "pending", fromUserId: "a" }),
    null,
  );
  assert.equal(
    resolveFriendRequestRecipient(undefined, {
      status: "pending",
      fromUserId: "a",
      toUserId: "a",
    }),
    null,
  );
});

test("本文は定型文、メッセージがあれば続ける", () => {
  assert.equal(friendRequestBody(null), FRIEND_REQUEST_BODY);
  assert.equal(friendRequestBody("  "), FRIEND_REQUEST_BODY);
  assert.equal(friendRequestBody(" よろしく "), `${FRIEND_REQUEST_BODY}：よろしく`);
});
