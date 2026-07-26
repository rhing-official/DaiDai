// 語らい内のメッセージに貼られた任意の外部URLのリンクプレビュー（タイトル・
// 説明文・サムネイル画像）を取得するAPI。
//
// ブラウザ（Flutterクライアント）から外部サイトへ直接fetchするとほとんどの
// サイトでCORSにより失敗するため、サーバー側（このVercel Function）で
// 代わりにHTMLを取得し、og:title等のメタタグだけを抜き出して返す。
// api/link-preview.jsとは逆方向（DaiDai自身のOGPを外部に見せるのではなく、
// 外部サイトのOGPをDaiDaiのクライアントに見せる）の役割を持つ。

const FETCH_TIMEOUT_MS = 5000;
const MAX_BODY_BYTES = 2 * 1024 * 1024; // 2MB読めれば大抵<head>は取得できる

module.exports = async (req, res) => {
  // このAPIはFlutterクライアントからブラウザのJS（fetch/XHR）経由で直接
  // 叩かれる。本番デプロイ先（dai-dai-phi.vercel.app）自身から呼ぶ分には
  // 同一オリジンなので問題ないが、ローカル開発サーバー（localhost:8765等）
  // から呼ぶと別オリジンへのクロスオリジンリクエストになり、この
  // ヘッダーが無いとブラウザ側でレスポンスがブロックされる
  // （実際にローカルでのみプレビューが表示されない不具合として発生した）。
  // 認証もCookieも使わない公開メタデータ取得のみのAPIのため、
  // オリジンを問わず許可して問題ない。
  res.setHeader('Access-Control-Allow-Origin', '*');

  const target = req.query.url;
  if (typeof target !== 'string' || !target) {
    res.status(400).json({ error: 'url is required' });
    return;
  }

  let parsed;
  try {
    parsed = new URL(target);
  } catch (e) {
    res.status(400).json({ error: 'invalid url' });
    return;
  }

  // http/https以外（file:, javascript: 等）やSSRFの入口になりやすい
  // ローカル/内部向けホストへのリクエストは拒否する。
  if (parsed.protocol !== 'http:' && parsed.protocol !== 'https:') {
    res.status(400).json({ error: 'unsupported scheme' });
    return;
  }
  if (isDisallowedHost(parsed.hostname)) {
    res.status(400).json({ error: 'host not allowed' });
    return;
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
      res.status(200).json({ url: parsed.toString(), title: null, description: null, image: null });
      return;
    }
    meta = parseOgTags(html);
    image = meta.image ? resolveUrl(meta.image, parsed) : null;
  }

  // このAPI自体の応答は毎回外部サイトへ取りに行くと重いため、Vercelのエッジ/
  // ブラウザ双方で短時間キャッシュする（同じURLが同じ語らい内で連続して
  // 表示される場合の負荷軽減）。
  res.setHeader('Cache-Control', 'public, max-age=300');
  res.status(200).json({
    url: parsed.toString(),
    title: meta.title,
    description: meta.description,
    image,
  });
};

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
          'Mozilla/5.0 (compatible; DaiDaiLinkPreview/1.0; +https://dai-dai-phi.vercel.app)',
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
