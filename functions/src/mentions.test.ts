import assert from "node:assert/strict";
import { test } from "node:test";

import { resolveMentionRecipients } from "./mentions";

const group = {
  senderId: "me",
  isDm: false,
  memberIds: ["owner", "me", "a", "b", "c"],
  ownerId: "owner",
  roleAssignments: { a: ["r1"], b: ["r1", "r2"], c: [] as string[] },
  memberPermissions: { me: [] as string[] },
};

test("個人宛: メンバーのみ有効で、送信者自身・非メンバーは除く", () => {
  const r = resolveMentionRecipients(
    { mentionedUserIds: ["a", "me", "stranger"] },
    group,
  );
  assert.deepEqual(r, ["a"]);
});

test("メンションが無い・全て無効ならnull（通常通知に戻す）", () => {
  assert.equal(resolveMentionRecipients({}, group), null);
  assert.equal(
    resolveMentionRecipients({ mentionedUserIds: ["stranger"] }, group),
    null,
  );
});

test("権限が無くても、広場なら@everyone（送信者以外の全員）に展開する", () => {
  const r = resolveMentionRecipients({ mentionEveryone: true }, group);
  assert.deepEqual(r?.sort(), ["a", "b", "c", "owner"]);
});

test("ロール宛はそのロールを持つメンバーに展開する（権限は不要）", () => {
  const r = resolveMentionRecipients(
    { mentionedRoleIds: ["r1"] },
    { ...group, senderId: "owner" },
  );
  assert.deepEqual(r?.sort(), ["a", "b"]);
});

test("一対では@everyone・ロール宛は常に無効", () => {
  const dm = { senderId: "me", isDm: true, memberIds: ["me", "you"] };
  assert.deepEqual(
    resolveMentionRecipients({ mentionedUserIds: ["you"] }, dm),
    ["you"],
  );
  assert.equal(
    resolveMentionRecipients({ mentionEveryone: true }, dm),
    null,
  );
});

test("配列でない・文字列でない値は無視する", () => {
  assert.equal(
    resolveMentionRecipients(
      { mentionedUserIds: "a", mentionedRoleIds: [1, null] },
      group,
    ),
    null,
  );
});
