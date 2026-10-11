import assert from "node:assert/strict";
import { test } from "node:test";

import { decideJoin, newMemberPermissions } from "./joinGroup";

test("承認必須（false以外）は拒否する", () => {
  assert.equal(decideJoin({ requiresApproval: true }, "u"), "denied");
  assert.equal(decideJoin({}, "u"), "denied");
});

test("承認不要なら参加できる", () => {
  assert.equal(decideJoin({ requiresApproval: false, memberIds: ["a"] }, "u"), "join");
});

test("既にメンバーなら冪等", () => {
  assert.equal(
    decideJoin({ requiresApproval: false, memberIds: ["u"] }, "u"),
    "already-member",
  );
});

test("新規メンバーの権限は基準ロールのもの", () => {
  assert.deepEqual(
    newMemberPermissions([
      { permissions: ["manageRooms"] },
      { isEveryone: true, permissions: ["createInvite"] },
    ]),
    ["createInvite"],
  );
  assert.deepEqual(newMemberPermissions([]), []);
});
