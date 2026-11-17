import assert from "node:assert/strict";
import { test } from "node:test";

import { MAX_ROLE_UPDATES, parseRoleUpdates } from "./stickerRoles";

test("役割の更新: 正しい入力は、空文字と重複を除いて通る", () => {
  const r = parseRoleUpdates([{ stickerId: "a", roles: ["greeting", "greeting", "", "thanks"] }]);
  assert.equal(r.ok, true);
  if (r.ok) assert.deepEqual(r.value, [{ stickerId: "a", roles: ["greeting", "thanks"] }]);
});

test("役割の更新: 空の配列でrolesを空にできる（役割なしに戻す）", () => {
  const r = parseRoleUpdates([{ stickerId: "a", roles: [] }]);
  assert.equal(r.ok, true);
});

test("役割の更新: 空・形式の誤り・stickerIdの重複・多すぎるときは拒否する", () => {
  assert.equal(parseRoleUpdates([]).ok, false);
  assert.equal(parseRoleUpdates("x").ok, false);
  assert.equal(parseRoleUpdates([{ stickerId: "", roles: [] }]).ok, false);
  assert.equal(parseRoleUpdates([{ stickerId: "a", roles: "greeting" }]).ok, false);
  assert.equal(parseRoleUpdates([{ stickerId: "a", roles: [] }, { stickerId: "a", roles: [] }]).ok, false);
  const many = Array.from({ length: MAX_ROLE_UPDATES + 1 }, (_, i) => ({ stickerId: `s${i}`, roles: [] }));
  assert.equal(parseRoleUpdates(many).ok, false);
});
