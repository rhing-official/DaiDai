import assert from "node:assert/strict";
import { test } from "node:test";

import { snsIconDataUri, snsIconNameFor } from "./snsIcons";

test("主要サービスは末尾一致でアイコンが決まる", () => {
  assert.equal(snsIconNameFor("https://x.com/foo"), "x");
  assert.equal(snsIconNameFor("https://twitter.com/foo"), "x");
  assert.equal(snsIconNameFor("https://www.note.com/foo"), "note");
  assert.equal(snsIconNameFor("https://m.youtube.com/watch?v=1"), "youtube");
  assert.equal(snsIconNameFor("https://gist.github.com/a"), "github");
});

test("別ドメイン・パース不可はアイコンなし", () => {
  assert.equal(snsIconNameFor("https://notex.com/a"), null);
  assert.equal(snsIconNameFor("https://x.com.evil.example/a"), null);
  assert.equal(snsIconNameFor("https://example.com"), null);
  assert.equal(snsIconNameFor("not a url"), null);
});

test("単色のdata URIを作る", () => {
  const uri = snsIconDataUri("x", "#fff");
  assert.ok(uri?.startsWith("data:image/svg+xml;base64,"));
  assert.equal(snsIconDataUri("nope", "#fff"), null);
});
