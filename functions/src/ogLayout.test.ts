import assert from "node:assert/strict";
import { test } from "node:test";

import { resolveOgLayout } from "./ogLayout";

test("未指定・不明な値は従来の左下・左揃え", () => {
  for (const [p, a] of [[undefined, undefined], ["nope", "nope"], [null, null]]) {
    const l = resolveOgLayout(p, a);
    assert.equal(l.justifyContent, "flex-end");
    assert.equal(l.alignSelfX, "flex-start");
    assert.equal(l.itemsAlign, "flex-start");
    assert.equal(l.textAlign, "left");
  }
});

test("プリセットごとの縦横位置と暗幕", () => {
  assert.deepEqual(
    [resolveOgLayout("bottomCenter", undefined).justifyContent, resolveOgLayout("bottomCenter", undefined).alignSelfX],
    ["flex-end", "center"],
  );
  assert.equal(resolveOgLayout("bottomRight", undefined).alignSelfX, "flex-end");
  const top = resolveOgLayout("topLeft", undefined);
  assert.equal(top.justifyContent, "flex-start");
  assert.ok(top.scrim.includes("to top"));
  const topRight = resolveOgLayout("topRight", undefined);
  assert.equal(topRight.justifyContent, "flex-start");
  assert.equal(topRight.alignSelfX, "flex-end");
  assert.ok(topRight.scrim.includes("to top"));
  const center = resolveOgLayout("center", undefined);
  assert.equal(center.justifyContent, "center");
  assert.equal(center.alignSelfX, "center");
});

test("文字の揃えは配置と独立", () => {
  const l = resolveOgLayout("bottomLeft", "end");
  assert.equal(l.alignSelfX, "flex-start");
  assert.equal(l.itemsAlign, "flex-end");
  assert.equal(l.textAlign, "right");
  assert.equal(resolveOgLayout("center", "center").textAlign, "center");
});
