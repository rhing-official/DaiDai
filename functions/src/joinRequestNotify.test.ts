import assert from "node:assert/strict";
import { test } from "node:test";

import {
  isNewPendingRequest,
  resolveJoinRequestRecipients,
} from "./joinRequestNotify";

test("長と権限者だけが宛先になり、申請者は除かれる", () => {
  const recipients = resolveJoinRequestRecipients(
    {
      ownerId: "owner",
      memberIds: ["owner", "mod", "plain"],
      memberPermissions: {
        mod: ["manageJoinRequests"],
        plain: ["createInvite"],
      },
    },
    "applicant",
  );
  assert.deepEqual(recipients.sort(), ["mod", "owner"]);
});

test("権限者が申請者本人なら除く", () => {
  const recipients = resolveJoinRequestRecipients(
    {
      ownerId: "owner",
      memberIds: ["mod"],
      memberPermissions: { mod: ["manageJoinRequests"] },
    },
    "mod",
  );
  assert.deepEqual(recipients, ["owner"]);
});

test("欠けたフィールドでも落ちない", () => {
  assert.deepEqual(resolveJoinRequestRecipients({}, "x"), []);
});

test("新規作成・再申請だけを通知対象にする", () => {
  assert.equal(isNewPendingRequest(undefined, { status: "pending" }), true);
  assert.equal(
    isNewPendingRequest({ status: "rejected" }, { status: "pending" }),
    true,
  );
  assert.equal(
    isNewPendingRequest({ status: "pending" }, { status: "pending" }),
    false,
  );
  assert.equal(
    isNewPendingRequest({ status: "pending" }, { status: "accepted" }),
    false,
  );
  assert.equal(isNewPendingRequest({ status: "pending" }, undefined), false);
});
