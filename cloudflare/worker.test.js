import test from 'node:test';
import assert from 'node:assert/strict';
import {
  parsePixivUrl,
  pixivPreviewFromAjax,
  isProxyableImageHost,
  userAgentsFor,
  decodeHtmlEntities,
  parseOgTags,
  isRelayHost,
  dropLoginWall,
} from './worker.js';

test('pixivのURL解析', () => {
  const p = (u) => parsePixivUrl(new URL(u));
  assert.deepEqual(p('https://www.pixiv.net/artworks/138266964'), { kind: 'artwork', id: '138266964' });
  assert.deepEqual(p('https://www.pixiv.net/en/artworks/1'), { kind: 'artwork', id: '1' });
  assert.deepEqual(p('https://www.pixiv.net/users/11'), { kind: 'user', id: '11' });
  assert.equal(p('https://example.com/users/11'), null);
  assert.equal(p('https://www.pixiv.net/'), null);
});

test('pixivアカウントは背景画像を中継URLでプレビューにする', () => {
  const r = pixivPreviewFromAjax(
    'user', '11',
    { name: '事務局', comment: 'a<br />b', imageBig: 'https://i.pximg.net/icon.jpg', background: { url: 'https://i.pximg.net/bg.png' } },
    'https://daidai.rhing.jp',
  );
  assert.equal(r.title, '事務局 - pixiv');
  assert.equal(r.description, 'a\nb');
  assert.equal(r.image, 'https://daidai.rhing.jp/api/url-preview-image?u=' + encodeURIComponent('https://i.pximg.net/bg.png'));
});

test('pixivアカウントは背景が無ければアイコン', () => {
  const r = pixivPreviewFromAjax('user', '1', { name: 'x', imageBig: 'https://i.pximg.net/icon.jpg', background: null }, 'https://o');
  assert.match(r.image, /icon\.jpg/);
});

test('pixiv作品は公式のOGP画像', () => {
  const r = pixivPreviewFromAjax('artwork', '138266964', { title: '心臓とモクレン', userName: 'チェリ子' }, 'https://o');
  assert.equal(r.title, '心臓とモクレン - チェリ子 - pixiv');
  assert.equal(r.image, 'https://embed.pixiv.net/artwork.php?illust_id=138266964');
});

test('画像の中継はi.pximg.netだけ許可', () => {
  assert.equal(isProxyableImageHost('i.pximg.net'), true);
  assert.equal(isProxyableImageHost('evil.example.com'), false);
  assert.equal(isProxyableImageHost('i.pximg.net.evil.com'), false);
});

test('Instagramはfacebookexternalhitを最優先', () => {
  assert.match(userAgentsFor('www.instagram.com')[0], /^facebookexternalhit/);
  assert.match(userAgentsFor('example.com')[0], /^Mozilla/);
});

test('数値文字参照・アポストロフィ入りのOGPを読める', () => {
  assert.equal(decodeHtmlEntities('M&#x30a;neskin &#064;x &quot;a&quot;'), 'M̊neskin @x "a"');
  const html = `<meta property="og:title" content="It's &quot;ok&quot;" /><meta property="og:image" content='https://x/y.jpg'>`;
  const og = parseOgTags(html);
  assert.equal(og.title, 'It\'s "ok"');
  assert.equal(og.image, 'https://x/y.jpg');
});

test('取得中継を使うのはpixiv・Instagramだけ', () => {
  assert.equal(isRelayHost('www.pixiv.net'), true);
  assert.equal(isRelayHost('pixiv.net'), true);
  assert.equal(isRelayHost('www.instagram.com'), true);
  assert.equal(isRelayHost('example.com'), false);
  assert.equal(isRelayHost('pixiv.net.evil.com'), false);
});

test('Instagramのログイン壁はプレビューとして使わない', () => {
  assert.equal(dropLoginWall({ title: 'ログイン • Instagram', description: null, image: null }).title, null);
  assert.equal(dropLoginWall({ title: 'Login • Instagram', description: 'x', image: 'y' }).image, null);
  assert.equal(dropLoginWall({ title: 'Måneskin (@maneskinofficial) • Instagram', description: null, image: null }).title, 'Måneskin (@maneskinofficial) • Instagram');
});
