import assert from "node:assert/strict";
import { test } from "node:test";

import { parseAllowedUrl, resolveReferer, resolveUserAgent } from "./urlFetchRelay";

test("許可ホスト（pixiv・Instagram）のhttpsだけ通す", () => {
  assert.ok(parseAllowedUrl("https://www.pixiv.net/artworks/1"));
  assert.ok(parseAllowedUrl("https://pixiv.net/users/11"));
  assert.ok(parseAllowedUrl("https://www.instagram.com/p/abc/"));
  assert.ok(parseAllowedUrl("https://instagram.com/x/"));
});

test("許可外・http・ポート・認証情報・詐称ホストは拒否する", () => {
  assert.equal(parseAllowedUrl("https://example.com/"), null);
  assert.equal(parseAllowedUrl("http://www.pixiv.net/"), null);
  assert.equal(parseAllowedUrl("https://www.pixiv.net:8443/"), null);
  assert.equal(parseAllowedUrl("https://user:pw@www.pixiv.net/"), null);
  assert.equal(parseAllowedUrl("https://www.pixiv.net.evil.com/"), null);
  assert.equal(parseAllowedUrl("https://evil.com/www.pixiv.net"), null);
  assert.equal(parseAllowedUrl("https://169.254.169.254/"), null);
  assert.equal(parseAllowedUrl("https://localhost/"), null);
  assert.equal(parseAllowedUrl("javascript:alert(1)"), null);
  assert.equal(parseAllowedUrl(undefined), null);
  assert.equal(parseAllowedUrl("https://www.pixiv.net/" + "a".repeat(3000)), null);
});

test("UAは許可リストの名前だけ、未知は既定（facebookexternalhit）", () => {
  assert.match(resolveUserAgent("Twitterbot"), /^Twitterbot/);
  assert.match(resolveUserAgent("evil"), /^facebookexternalhit/);
  assert.match(resolveUserAgent(undefined), /^facebookexternalhit/);
});

test("Refererは許可ホストのオリジンだけ", () => {
  assert.equal(resolveReferer("https://www.pixiv.net/artworks/1"), "https://www.pixiv.net/");
  assert.equal(resolveReferer("https://evil.com/"), undefined);
});
