import assert from "node:assert/strict";
import { test } from "node:test";

import {
  SNS_OFFICIAL_ICON_SVGS,
  cssColorLuminance,
  snsIconDataUri,
  snsIconNameFor,
} from "./snsIcons";

test("主要サービスは末尾一致でアイコンが決まる", () => {
  assert.equal(snsIconNameFor("https://x.com/foo"), "x");
  assert.equal(snsIconNameFor("https://twitter.com/foo"), "x");
  assert.equal(snsIconNameFor("https://www.note.com/foo"), "note");
  assert.equal(snsIconNameFor("https://gist.github.com/a"), "github");
});

test("YouTubeは、チャンネルのURLのときだけアイコンが出る", () => {
  assert.equal(snsIconNameFor("https://www.youtube.com/@foo"), "youtube");
  assert.equal(snsIconNameFor("https://m.youtube.com/@Foo/videos"), "youtube");
  assert.equal(snsIconNameFor("https://youtube.com/channel/UCabc"), "youtube");
  assert.equal(snsIconNameFor("https://youtube.com/c/foo"), "youtube");
  assert.equal(snsIconNameFor("https://youtube.com/user/foo"), "youtube");
  assert.equal(snsIconNameFor("https://m.youtube.com/watch?v=1"), null);
  assert.equal(snsIconNameFor("https://youtu.be/abc"), null);
  assert.equal(snsIconNameFor("https://youtube.com/playlist?list=1"), null);
  assert.equal(snsIconNameFor("https://youtube.com/shorts/abc"), null);
  assert.equal(snsIconNameFor("https://youtube.com"), null);
});

test("別ドメイン・パース不可はアイコンなし", () => {
  assert.equal(snsIconNameFor("https://notex.com/a"), null);
  assert.equal(snsIconNameFor("https://x.com.evil.example/a"), null);
  assert.equal(snsIconNameFor("https://example.com"), null);
  assert.equal(snsIconNameFor("not a url"), null);
});

test("公式のロゴのdata URIを、背景の明るさで黒／白に切り替える", () => {
  const decode = (uri: string | null) =>
    Buffer.from(uri!.split(",")[1], "base64").toString("utf-8");
  // 文字色が明るい（背景が暗い）なら白の版、暗いなら黒（Zennは青）の版。
  const dark = snsIconDataUri("bluesky", "rgba(255,255,255,0.75)");
  const light = snsIconDataUri("bluesky", "rgba(0,0,0,0.75)");
  assert.ok(dark?.startsWith("data:image/svg+xml;base64,"));
  assert.equal(decode(dark), SNS_OFFICIAL_ICON_SVGS.bluesky.dark);
  assert.equal(decode(light), SNS_OFFICIAL_ICON_SVGS.bluesky.light);
  assert.notEqual(decode(dark), decode(light));
  assert.equal(decode(snsIconDataUri("zenn", "#fff")), SNS_OFFICIAL_ICON_SVGS.zenn.dark);
  // 公式素材を同梱していないサービスはnull（OGPはドメインの文字を出す）。
  assert.equal(snsIconDataUri("x", "#fff"), null);
  assert.equal(snsIconDataUri("nope", "#fff"), null);
  assert.equal(cssColorLuminance("not a color"), null);
});

test("同梱のロゴが、アプリ側のSVGと同じ内容", () => {
  // eslint-disable-next-line @typescript-eslint/no-require-imports
  const fs = require("node:fs");
  for (const [name, svg] of Object.entries(SNS_OFFICIAL_ICON_SVGS)) {
    assert.equal(fs.readFileSync(`../assets/sns_icons/${name}.svg`, "utf-8").trim(), svg.light);
    assert.equal(fs.readFileSync(`../assets/sns_icons/${name}-white.svg`, "utf-8").trim(), svg.dark);
  }
});
