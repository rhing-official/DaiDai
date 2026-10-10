// Cloudflare Pages の Advanced Mode Worker（`build/web/_worker.js`としてデプロイされる）。
// Vercel Functionsだった`api/link-preview.js`・`api/url-preview.js`をWorkers向けに
// 移植したもの（2026-10-10、VercelからCloudflareへの移行）。移植元のコメントに
// 書かれていた経緯・仕様はそれぞれのファイルを参照。
//
// ルーティング（`_routes.json`でこのWorkerを通すパスを限定している）:
//   /invite/:rhingSeed, /join/:groupId[/:cacheBust] → OGPタグを差し込んだindex.html
//   /api/url-preview?url=...                         → 外部URLのリンクプレビュー
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
    if (path === '/api/url-preview') return urlPreview(url);
    if (path === '/api/og-image') return ogImage(url, env);
    if (/^\/invite\/[^/]+\/?$/.test(path) || /^\/join\/[^/]+(?:\/[^/]+)?\/?$/.test(path)) {
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
  const inviteMatch = url.pathname.match(/^\/invite\/([^/]+)\/?$/);
  const joinMatch = url.pathname.match(/^\/join\/([^/]+)(?:\/([^/]+))?\/?$/);

  let title = 'DaiDai';
  let description = '整う、守る、私に馴染む。DaiDai';
  let image = null;

  try {
    if (inviteMatch) {
      const rhingSeed = decodeURIComponent(inviteMatch[1]);
      const doc = await fetchFirestoreDoc(`userInvites/${rhingSeed}`);
      if (doc) {
        title = doc.nickname ? `${doc.nickname}（@${rhingSeed}）` : `@${rhingSeed}`;
        description = 'DaiDaiで仲間になりましょう';
        image = doc.iconUrl
          ? `https://${host}/api/og-image?type=user&id=${encodeURIComponent(rhingSeed)}`
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

  let html;
  try {
    const indexRes = await env.ASSETS.fetch(new Request(new URL('/index.html', url), request));
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

async function urlPreview(url) {
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

  const youtubePreview = isYouTubeHost(parsed.hostname)
    ? await fetchYouTubeOEmbed(parsed.toString())
    : null;

  let meta;
  let image;
  if (youtubePreview) {
    meta = youtubePreview;
    image = youtubePreview.image;
  } else {
    let html;
    try {
      html = await fetchTextWithLimit(parsed.toString());
    } catch (e) {
      return json({ url: parsed.toString(), title: null, description: null, image: null });
    }
    meta = parseOgTags(html);
    image = meta.image ? resolveUrl(meta.image, parsed) : null;
  }

  return json(
    { url: parsed.toString(), title: meta.title, description: meta.description, image },
    200,
    { 'Cache-Control': 'public, max-age=300' },
  );
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

async function fetchTextWithLimit(url) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), FETCH_TIMEOUT_MS);
  try {
    const response = await fetch(url, {
      signal: controller.signal,
      redirect: 'follow',
      headers: {
        // 一部サイトはUser-Agent無しのリクエストを弾くため、一般的な
        // クローラーに偽装せず、素直にブラウザ風のUAを名乗る。
        'User-Agent':
          'Mozilla/5.0 (compatible; DaiDaiLinkPreview/1.0; +https://daidai.rhing.jp)',
        // Googleのサービス（YouTube含む）はリージョンによってGDPR同意の
        // 中間ページを返すことがあるため、同意済みのCookieを付けて回避する。
        Cookie: 'CONSENT=YES+',
      },
    });
    if (!response.ok || !response.body) return '';
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
    return text;
  } finally {
    clearTimeout(timeout);
  }
}

function parseOgTags(html) {
  const getMeta = (prop) => {
    const re = new RegExp(
      `<meta[^>]+(?:property|name)=["']${prop}["'][^>]+content=["']([^"']*)["']`,
      'i',
    );
    const match = html.match(re);
    return match ? decodeHtmlEntities(match[1]) : null;
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

function decodeHtmlEntities(str) {
  return str
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'");
}
