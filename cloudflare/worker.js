// Cloudflare Pages の Advanced Mode Worker（`build/web/_worker.js`としてデプロイされる）。
// Vercel Functionsだった`api/link-preview.js`・`api/url-preview.js`をWorkers向けに
// 移植したもの（2026-10-10、VercelからCloudflareへの移行）。移植元のコメントに
// 書かれていた経緯・仕様はそれぞれのファイルを参照。
//
// ルーティング（`_routes.json`でこのWorkerを通すパスを限定している）:
//   /invite/:rhingSeed, /join/:groupId[/:cacheBust] → OGPタグを差し込んだindex.html
//   /api/url-preview?url=...                         → 外部URLのリンクプレビュー
//   /api/url-preview-image?u=...                     → pixivの画像（Referer必須）の中継
//   /api/og-image?type=&id=                          → OG画像（`OG_IMAGE_ORIGIN`のバックエンドへ中継）
// それ以外は静的アセット（Pagesが未知のパスにindex.htmlを返すSPAフォールバック込み）。

const FIRESTORE_PROJECT_ID = 'daidai-rhing';
const OG_IMAGE_WIDTH = 1200;
const OG_IMAGE_HEIGHT = 1500;
const FETCH_TIMEOUT_MS = 5000;
const MAX_BODY_BYTES = 2 * 1024 * 1024;

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const path = url.pathname;
    if (path === '/api/url-preview') return urlPreview(url, env);
    if (path === '/api/url-preview-image') return previewImage(url);
    if (path === '/api/og-image') return ogImage(url, env);
    if (/^\/invite\/[^/]+(?:\/[^/]+)?\/?$/.test(path) || /^\/join\/[^/]+(?:\/[^/]+)?\/?$/.test(path)) {
      return linkPreview(request, url, env);
    }
    return env.ASSETS.fetch(request);
  },
};

// OG画像の生成（satori/resvg/sharp）はWorkersでは動かせないため、Node.jsで動く
// バックエンド（Cloud Functions）に中継する。`OG_IMAGE_ORIGIN`（Pagesの環境変数）が
// 未設定なら404（OGPの画像だけ出ない。招待リンク自体は開ける）。
async function ogImage(url, env) {
  if (!env.OG_IMAGE_ORIGIN) return new Response('not found', { status: 404 });
  const upstream = new URL(env.OG_IMAGE_ORIGIN);
  upstream.search = url.search;
  const res = await fetch(upstream.toString());
  return new Response(res.body, {
    status: res.status,
    headers: {
      'Content-Type': res.headers.get('Content-Type') ?? 'image/png',
      'Cache-Control': 'public, max-age=300',
    },
  });
}

async function linkPreview(request, url, env) {
  const host = url.host;
  const inviteMatch = url.pathname.match(/^\/invite\/([^/]+)(?:\/([^/]+))?\/?$/);
  const joinMatch = url.pathname.match(/^\/join\/([^/]+)(?:\/([^/]+))?\/?$/);

  let title = 'DaiDai';
  let description = '整う、守る、私に馴染む。DaiDai';
  let image = null;

  try {
    if (inviteMatch) {
      const rhingSeed = decodeURIComponent(inviteMatch[1]);
      // 末尾の版識別子（アプリの招待リンクがカードの内容から付ける）をOG画像のURLにも
      // 付け、カードを変えたら外部アプリ（Discord・LINE等）が別の画像として取り直す。
      const inviteBust = inviteMatch[2] ? `&v=${encodeURIComponent(inviteMatch[2])}` : '';
      const doc = await fetchFirestoreDoc(`userInvites/${rhingSeed}`);
      if (doc) {
        title = doc.nickname ? `${doc.nickname}（@${rhingSeed}）` : `@${rhingSeed}`;
        description = 'DaiDaiで仲間になりましょう';
        image = doc.iconUrl
          ? `https://${host}/api/og-image?type=user&id=${encodeURIComponent(rhingSeed)}${inviteBust}`
          : null;
      }
    } else if (joinMatch) {
      const groupId = decodeURIComponent(joinMatch[1]);
      const cacheBust = joinMatch[2] ? `&v=${encodeURIComponent(joinMatch[2])}` : '';
      const doc = await fetchFirestoreDoc(`groupInvites/${groupId}`);
      if (doc) {
        title = doc.name || title;
        description = doc.description || 'DaiDaiの広場に参加しましょう';
        image = doc.iconUrl || doc.backgroundImageUrl
          ? `https://${host}/api/og-image?type=group&id=${encodeURIComponent(groupId)}${cacheBust}`
          : null;
      }
    }
  } catch (e) {
    // Firestore取得に失敗しても既定のOGタグでページ自体は返す。
  }

  // `/index.html`はPagesが`/`へ308リダイレクトするため、最初から`/`を取る。
  let html;
  try {
    const indexRes = await env.ASSETS.fetch(new Request(new URL('/', url), request));
    if (!indexRes.ok) throw new Error(`index status ${indexRes.status}`);
    html = await indexRes.text();
  } catch (e) {
    return new Response('index.html not available', { status: 502 });
  }

  const ogTags = [
    `<meta property="og:site_name" content="DaiDai">`,
    `<meta property="og:title" content="${escapeHtml(title)}">`,
    `<meta property="og:description" content="${escapeHtml(description)}">`,
    `<meta property="og:url" content="${escapeHtml(url.toString())}">`,
    image ? `<meta property="og:image" content="${escapeHtml(image)}">` : '',
    image ? `<meta property="og:image:width" content="${OG_IMAGE_WIDTH}">` : '',
    image ? `<meta property="og:image:height" content="${OG_IMAGE_HEIGHT}">` : '',
    `<meta name="twitter:card" content="${image ? 'summary_large_image' : 'summary'}">`,
  ].filter(Boolean).join('\n    ');

  html = html.replace('</head>', `    ${ogTags}\n  </head>`);
  return new Response(html, {
    status: 200,
    headers: { 'Content-Type': 'text/html; charset=utf-8' },
  });
}

function json(body, status = 200, extra = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      'Content-Type': 'application/json; charset=utf-8',
      // ローカル開発サーバー（localhost:8765等）からのクロスオリジン呼び出し用
      // （認証・Cookieを使わない公開メタデータ取得のみのため全許可）。
      'Access-Control-Allow-Origin': '*',
      ...extra,
    },
  });
}

async function urlPreview(url, env) {
  const target = url.searchParams.get('url');
  if (!target) return json({ error: 'url is required' }, 400);

  let parsed;
  try {
    parsed = new URL(target);
  } catch (e) {
    return json({ error: 'invalid url' }, 400);
  }
  if (parsed.protocol !== 'http:' && parsed.protocol !== 'https:') {
    return json({ error: 'unsupported scheme' }, 400);
  }
  if (isDisallowedHost(parsed.hostname)) {
    return json({ error: 'host not allowed' }, 400);
  }

  const debug = url.searchParams.get('debug') === '1';
  const oembed = isYouTubeHost(parsed.hostname)
    ? await fetchYouTubeOEmbed(parsed.toString())
    : (await fetchPixivPreview(parsed, url.origin, env)) ??
      (await fetchSiteOEmbed(parsed));

  let meta;
  let image;
  const trace = [];
  if (oembed) {
    meta = oembed;
    image = oembed.image;
  } else {
    meta = { title: null, description: null, image: null };
    // pixiv等はデータセンターからのアクセスや一般的なUAを弾くことがあるため、
    // 取れなかった時はリンク展開bot向けのUAで順に取り直す。
    let relayTried = false;
    for (const ua of userAgentsFor(parsed.hostname)) {
      let result;
      try {
        result = await fetchTextWithLimit(parsed.toString(), ua);
      } catch (e) {
        trace.push(`${ua.split('/')[0]}:error`);
        continue;
      }
      trace.push(`${ua.split('/')[0]}:${result.status}`);
      let found = dropLoginWall(parseOgTags(result.text));
      if (!(found.title || found.description || found.image)) {
        // 直接の取得が弾かれた（403/429等）pixiv・Instagramは、Google Cloudの
        // 取得中継（`urlFetchRelay`）から取り直す。
        const relayed = relayTried ? null : await relayFetch(env, parsed.toString(), ua);
        relayTried = relayTried || relayed !== null;
        if (relayed) {
          trace.push(`relay-${ua.split('/')[0]}:${relayed.status}`);
          found = dropLoginWall(parseOgTags(relayed.text));
        }
      }
      if (found.title || found.description || found.image) {
        meta = found;
        break;
      }
    }
    image = meta.image ? resolveUrl(meta.image, parsed) : null;
  }

  // 取れなかったサイト別の補完（HTMLを取らずに作れるもの）。
  const fallback = siteFallback(parsed, url.origin);
  if (fallback) {
    meta = { ...meta, title: meta.title || fallback.title };
    image = image || fallback.image;
  }

  const empty = !meta.title && !meta.description && !image;
  const body = { url: parsed.toString(), title: meta.title, description: meta.description, image };
  if (debug) body.debug = trace;
  return json(body, 200, {
    // 取れなかった時は短くして、復旧が早く反映されるようにする。
    'Cache-Control': empty ? 'public, max-age=60' : 'public, max-age=300',
  });
}

// Instagramはリンク展開bot（facebookexternalhit）にだけOGPを返すため最優先にする。
export function userAgentsFor(hostname) {
  const host = hostname.toLowerCase().replace(/^www\./, '');
  if (host === 'instagram.com') return [USER_AGENTS[2], USER_AGENTS[1], USER_AGENTS[3], USER_AGENTS[0]];
  return USER_AGENTS;
}

const USER_AGENTS = [
  'Mozilla/5.0 (compatible; DaiDaiLinkPreview/1.0; +https://daidai.rhing.jp)',
  'Twitterbot/1.0',
  'facebookexternalhit/1.1 (+http://www.facebook.com/externalhit_uatext.php)',
  'Discordbot/2.0',
];

// pixivのURLを解析する。作品（/artworks/{id}）かアカウント（/users/{id}）。
export function parsePixivUrl(parsed) {
  const host = parsed.hostname.toLowerCase().replace(/^www\./, '');
  if (host !== 'pixiv.net') return null;
  const art = parsed.pathname.match(/^\/(?:[a-z]{2}\/)?artworks\/(\d+)/);
  if (art) return { kind: 'artwork', id: art[1] };
  const user = parsed.pathname.match(/^\/(?:[a-z]{2}\/)?users\/(\d+)/);
  if (user) return { kind: 'user', id: user[1] };
  return null;
}

// Referer無しだと403になる画像ホスト。中継を許すのはここだけ（SSRF対策）。
export function isProxyableImageHost(hostname) {
  return hostname.toLowerCase() === 'i.pximg.net';
}

function proxiedImageUrl(origin, imageUrl) {
  return `${origin}/api/url-preview-image?u=${encodeURIComponent(imageUrl)}`;
}

// pixivのajaxの結果から (title, description, image) を作る。
export function pixivPreviewFromAjax(kind, id, body, origin) {
  if (kind === 'artwork') {
    return {
      title: body.title
        ? [body.title, body.userName, 'pixiv'].filter(Boolean).join(' - ')
        : 'pixiv',
      description: body.description ? stripTags(body.description) : null,
      // 画像は投稿の本体画像（`urls.regular`、i.pximg.net）をこのWorkerの中継
      // （Referer付き・CORS付き）経由で出す。公式のOGP画像（embed.pixiv.net）は
      // CORSヘッダーが無くFlutter Webで読めず、Cloudflareからの取得も弾かれる。
      image: (() => {
        const urls = body.urls || {};
        const picture = urls.regular || urls.small || urls.thumb || null;
        return picture ? proxiedImageUrl(origin, picture) : null;
      })(),
    };
  }
  const bg = body.background && body.background.url;
  const picture = bg || body.imageBig || null;
  return {
    title: body.name ? `${body.name} - pixiv` : 'pixiv',
    description: body.comment ? stripTags(body.comment) : null,
    image: picture ? proxiedImageUrl(origin, picture) : null,
  };
}

function stripTags(html) {
  return decodeHtmlEntities(String(html).replace(/<br\s*\/?>/gi, '\n').replace(/<[^>]+>/g, '')).trim();
}

async function fetchPixivPreview(parsed, origin, env) {
  const target = parsePixivUrl(parsed);
  if (!target) return null;
  const endpoint =
    target.kind === 'artwork'
      ? `https://www.pixiv.net/ajax/illust/${target.id}`
      : `https://www.pixiv.net/ajax/user/${target.id}?full=1`;
  let data = await fetchJsonDirect(endpoint);
  if (!data || data.error || !data.body) {
    // CloudflareのIPからは403になるため、取得中継（Google CloudのIP）から取り直す。
    const relayed = await relayFetch(env, endpoint, USER_AGENTS[0], 'https://www.pixiv.net/');
    if (relayed && relayed.status === 200) {
      try {
        data = JSON.parse(relayed.text);
      } catch (e) {
        data = null;
      }
    }
  }
  if (!data || data.error || !data.body) return null;
  return pixivPreviewFromAjax(target.kind, target.id, data.body, origin);
}

async function fetchJsonDirect(endpoint) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), FETCH_TIMEOUT_MS);
  try {
    const response = await fetch(endpoint, {
      signal: controller.signal,
      headers: { 'User-Agent': USER_AGENTS[0], Referer: 'https://www.pixiv.net/' },
    });
    if (!response.ok) return null;
    return await response.json();
  } catch (e) {
    return null;
  } finally {
    clearTimeout(timeout);
  }
}

// Google Cloudの取得中継（Cloud Functions `urlFetchRelay`）。`URL_FETCH_RELAY_ORIGIN`
// （Pagesの環境変数、未設定なら既定のURL）で上書きできる。取得先が中継の許可ホスト以外なら使わない。
export function isRelayHost(hostname) {
  const host = hostname.toLowerCase().replace(/^www\./, '');
  return host === 'pixiv.net' || host === 'instagram.com';
}

// 既定の中継先（公開の関数URL。許可ホストしか取得できない）。環境変数で上書きできる。
const DEFAULT_RELAY_ORIGIN = 'https://asia-northeast1-daidai-rhing.cloudfunctions.net/urlFetchRelay';

async function relayFetch(env, target, userAgent, referer) {
  const origin = (env && env.URL_FETCH_RELAY_ORIGIN) || DEFAULT_RELAY_ORIGIN;
  let parsed;
  try {
    parsed = new URL(target);
  } catch (e) {
    return null;
  }
  if (!isRelayHost(parsed.hostname)) return null;
  const relayUrl = new URL(origin);
  relayUrl.searchParams.set('url', target);
  relayUrl.searchParams.set('ua', userAgent.split('/')[0].split(' ')[0]);
  if (referer) relayUrl.searchParams.set('referer', referer);
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 10000);
  try {
    const response = await fetch(relayUrl.toString(), { signal: controller.signal });
    if (!response.ok) return null;
    const data = await response.json();
    return { status: Number(data.status) || 0, text: typeof data.text === 'string' ? data.text : '' };
  } catch (e) {
    return null;
  } finally {
    clearTimeout(timeout);
  }
}

// pixivの画像（Referer必須）を、Refererを付けて取得して返す。
async function previewImage(url) {
  const target = url.searchParams.get('u');
  let parsed;
  try {
    parsed = new URL(target ?? '');
  } catch (e) {
    return new Response('bad request', { status: 400 });
  }
  if (parsed.protocol !== 'https:' || !isProxyableImageHost(parsed.hostname)) {
    return new Response('host not allowed', { status: 400 });
  }
  const res = await fetch(parsed.toString(), {
    headers: { Referer: 'https://www.pixiv.net/', 'User-Agent': USER_AGENTS[0] },
  });
  if (!res.ok) return new Response('upstream error', { status: 502 });
  return new Response(res.body, {
    status: 200,
    headers: {
      'Content-Type': res.headers.get('Content-Type') ?? 'image/jpeg',
      'Cache-Control': 'public, max-age=86400',
      'Access-Control-Allow-Origin': '*',
    },
  });
}

// 公開oEmbedがあるサイト（HTML取得を弾かれても確実に取れる）。
async function fetchSiteOEmbed(parsed) {
  const host = parsed.hostname.toLowerCase().replace(/^www\./, '');
  let endpoint = null;
  if (host === 'tiktok.com') endpoint = 'https://www.tiktok.com/oembed?url=';
  else if (host === 'reddit.com') endpoint = 'https://www.reddit.com/oembed?url=';
  if (!endpoint) return null;
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), FETCH_TIMEOUT_MS);
  try {
    const response = await fetch(endpoint + encodeURIComponent(parsed.toString()), {
      signal: controller.signal,
      headers: { 'User-Agent': USER_AGENTS[0] },
    });
    if (!response.ok) return null;
    const data = await response.json();
    if (!data.title && !data.thumbnail_url) return null;
    return {
      title: data.title ?? null,
      description: data.author_name ? `投稿者: ${data.author_name}` : null,
      image: data.thumbnail_url ?? null,
    };
  } catch (e) {
    return null;
  } finally {
    clearTimeout(timeout);
  }
}

// HTMLが取れなかった時の補完。pixiv作品はOGPと同じ形式の画像URLを組み立てられる。
function siteFallback(parsed, origin) {
  const host = parsed.hostname.toLowerCase().replace(/^www\./, '');
  if (host === 'pixiv.net') {
    return {
      title: 'pixiv',
      image: null,
    };
  }
  return null;
}

async function fetchFirestoreDoc(path) {
  const url =
    `https://firestore.googleapis.com/v1/projects/${FIRESTORE_PROJECT_ID}` +
    `/databases/(default)/documents/${path}`;
  const res = await fetch(url);
  if (!res.ok) return null;
  const json = await res.json();
  return parseFirestoreFields(json.fields);
}

function parseFirestoreFields(fields) {
  if (!fields) return null;
  const result = {};
  for (const [key, value] of Object.entries(fields)) {
    if ('stringValue' in value) result[key] = value.stringValue;
    else if ('nullValue' in value) result[key] = null;
  }
  return result;
}

function escapeHtml(str) {
  return String(str).replace(/[&<>"']/g, (c) => ({
    '&': '&amp;',
    '<': '&lt;',
    '>': '&gt;',
    '"': '&quot;',
    "'": '&#39;',
  }[c]));
}

function isDisallowedHost(hostname) {
  const lower = hostname.toLowerCase();
  if (lower === 'localhost' || lower.endsWith('.local')) return true;
  // IPv4リテラルのプライベート/ループバック/リンクローカル帯域。
  const ipv4 = lower.match(/^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/);
  if (ipv4) {
    const [a, b] = [Number(ipv4[1]), Number(ipv4[2])];
    if (a === 127 || a === 10 || a === 0) return true;
    if (a === 169 && b === 254) return true;
    if (a === 172 && b >= 16 && b <= 31) return true;
    if (a === 192 && b === 168) return true;
  }
  if (lower === '::1' || lower === '[::1]') return true;
  return false;
}

function isYouTubeHost(hostname) {
  const lower = hostname.toLowerCase();
  return (
    lower === 'youtube.com' ||
    lower === 'www.youtube.com' ||
    lower === 'm.youtube.com' ||
    lower === 'youtu.be'
  );
}

// YouTubeの動画ページはHTMLスクレイピングだとGDPR同意の中間ページが
// 返ってくることがあり（Vercel Functionの実行リージョン次第で発生、
// タイトル・説明文・画像が動画と無関係な汎用的な内容になってしまう
// 不具合として実際に確認した）、公式のoEmbed APIの方が確実。
async function fetchYouTubeOEmbed(url) {
  const endpoint = `https://www.youtube.com/oembed?url=${encodeURIComponent(url)}&format=json`;
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), FETCH_TIMEOUT_MS);
  try {
    const response = await fetch(endpoint, { signal: controller.signal });
    if (!response.ok) return null;
    const json = await response.json();
    return {
      title: json.title ?? null,
      description: json.author_name ? `投稿者: ${json.author_name}` : null,
      image: json.thumbnail_url ?? null,
    };
  } catch (e) {
    return null;
  } finally {
    clearTimeout(timeout);
  }
}

async function fetchTextWithLimit(url, userAgent) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), FETCH_TIMEOUT_MS);
  try {
    const response = await fetch(url, {
      signal: controller.signal,
      redirect: 'follow',
      headers: {
        // 一部サイトはUser-Agent無しのリクエストを弾くため、一般的な
        // クローラーに偽装せず、素直にブラウザ風のUAを名乗る。
        'User-Agent': userAgent,
        // Googleのサービス（YouTube含む）はリージョンによってGDPR同意の
        // 中間ページを返すことがあるため、同意済みのCookieを付けて回避する。
        Cookie: 'CONSENT=YES+',
      },
    });
    if (!response.ok || !response.body) return { status: response.status, text: '' };
    const reader = response.body.getReader();
    const decoder = new TextDecoder();
    let received = 0;
    let text = '';
    while (received < MAX_BODY_BYTES) {
      const { done, value } = await reader.read();
      if (done) break;
      received += value.length;
      text += decoder.decode(value, { stream: true });
    }
    await reader.cancel().catch(() => {});
    return { status: response.status, text };
  } finally {
    clearTimeout(timeout);
  }
}

// ログインを求める壁（Instagramのアカウントページを非ログインで取ると返る）は、
// プレビューとして無意味なので取得失敗として扱う。
export function dropLoginWall(meta) {
  const title = (meta.title || '').trim();
  if (/^(ログイン|log ?in)(\s|•|$).*instagram/i.test(title)) {
    return { title: null, description: null, image: null };
  }
  return meta;
}

export function parseOgTags(html) {
  const getMeta = (prop) => {
    const re = new RegExp(
      `<meta[^>]+(?:property|name)=["']${prop}["'][^>]+content=(?:"([^"]*)"|'([^']*)')`,
      'i',
    );
    const match = html.match(re);
    const value = match ? (match[1] ?? match[2]) : null;
    return value == null ? null : decodeHtmlEntities(value);
  };
  const titleTagMatch = html.match(/<title[^>]*>([^<]*)<\/title>/i);

  return {
    title: getMeta('og:title') || (titleTagMatch ? decodeHtmlEntities(titleTagMatch[1]) : null),
    description: getMeta('og:description') || getMeta('description'),
    image: getMeta('og:image'),
  };
}

function resolveUrl(maybeRelative, baseUrl) {
  try {
    return new URL(maybeRelative, baseUrl).toString();
  } catch (e) {
    return null;
  }
}

export function decodeHtmlEntities(str) {
  return str
    .replace(/&#x([0-9a-f]+);/gi, (_, h) => safeCodePoint(parseInt(h, 16)))
    .replace(/&#(\d+);/g, (_, d) => safeCodePoint(parseInt(d, 10)))
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&amp;/g, '&');
}

function safeCodePoint(n) {
  try {
    return String.fromCodePoint(n);
  } catch (e) {
    return '';
  }
}
