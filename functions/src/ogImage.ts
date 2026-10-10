// OGP画像（招待リンクのカード）の生成。Vercel Functionの`api/og-image.mjs`を
// Cloud Functionsへ移植したもの（2026-10-10、VercelからCloudflareへの移行。
// Cloudflare WorkersではSatori/resvg/sharpが動かないためNode.jsのここで生成し、
// Pages側のWorkerが`/api/og-image`をこの関数へ中継する）。デザインの経緯
// （4:5固定・`ProfileCardView`とのpx対応・WebPをsharpでPNG化する理由）は
// 移植元のコメント（git履歴の`api/og-image.mjs`）を参照。
/* eslint-disable @typescript-eslint/no-explicit-any */
import sharp from "sharp";

// @vercel/ogはESM専用。Node 24のrequire(esm)で同期的に読み込む。
// eslint-disable-next-line @typescript-eslint/no-require-imports
const { ImageResponse } = require("@vercel/og");

const FIRESTORE_PROJECT_ID = 'daidai-rhing';
// 4:5比率を維持したまま解像度を引き上げている（2026-09-25、800x1000から
// 1.5倍。埋め込みカードの表示幅自体は各SNS側のレイアウトに依存し
// 強制はできないが、iMessage等の画像実解像度に応じてカードサイズを
// 決めるタイプのリンクプレビューでは表示が大きくなる場合がある）。
const CARD_WIDTH = 1200;
const CARD_HEIGHT = 1500;

// `ProfileCardView`の固定値（想定カード幅480pxに対するもの）をCARD_WIDTHへ
// スケールする倍率。
const SCALE = CARD_WIDTH / 480;
const ICON_SIZE = 64 * 2 * SCALE; // kProfileCardAvatarRadius×2（直径）
const CONTENT_PADDING = 32 * SCALE; // kProfileCardPadding
const NAME_FONT_SIZE = 28 * SCALE; // kProfileCardNicknameFontSize
const DESCRIPTION_FONT_SIZE = 18 * SCALE; // kProfileCardStatusFontSize
const SNS_FONT_SIZE = DESCRIPTION_FONT_SIZE * 0.9;
const ICON_NAME_GAP = CONTENT_PADDING * 0.6;
const SNS_LINKS_GAP = CONTENT_PADDING * 0.3;

function el(type: string, style: any, children: any) {
  return { type, props: { style, children } };
}

function img(src: string, style: any) {
  return { type: 'img', props: { src, style } };
}

// Node.js Runtimeでは`export default`は旧来の`(req, res) => void`シグネチャ専用で、
// Web標準のRequest/Responseを使う場合は`GET`等HTTPメソッド名の名前付きexportに
// する必要がある（実機検証で判明: `export default`のままだとレスポンスが
// 無視され、Vercelのハードタイムアウト=300秒までリクエストがハングし続けていた。
// Vercel側のワーニングログにもこの修正方法が明記されている）。
async function render(type: string | null, id: string | null): Promise<Buffer> {

  let doc: any = null;
  if (type === 'user' && id) {
    doc = await fetchFirestoreDoc(`userInvites/${id}`);
  } else if (type === 'group' && id) {
    doc = await fetchFirestoreDoc(`groupInvites/${id}`);
  }

  const isUser = type === 'user';
  const name = doc
    ? (isUser ? doc.nickname || `@${id}` : doc.name || 'DaiDai')
    : 'DaiDai';
  const description = doc
    ? (isUser ? doc.statusMessage : doc.description) || ''
    : '';
  const snsLinks = isUser
    ? parseSnsLinkUrls(doc?.snsLinkUrls).slice(0, 2).map(displaySnsLinkUrl)
    : [];

  // WebP画像をそのままSatoriに渡すと描画に失敗するため、事前にPNGへ変換する。
  // 変換自体が失敗しても（画像取得失敗等）画像抜きでカードは生成できるよう、
  // 個別にcatchしてnullにフォールバックする。
  // フォント取得（Google Fontsへの2回の往復）は画像変換と依存関係が無いため、
  // 直列にせず同じPromise.allで並列に走らせて待ち時間を短縮する。
  const fontText = `${name}${description}${snsLinks.join('')}DaiDai`;
  const [iconDataUri, backgroundDataUri, fontData] = await Promise.all([
    doc?.iconUrl ? toPngDataUri(doc.iconUrl).catch(() => null) : null,
    doc?.backgroundImageUrl
      ? toPngDataUri(doc.backgroundImageUrl).catch(() => null)
      : null,
    loadNotoSansJpCached(fontText).catch(() => null),
  ]);
  const hasBackground = Boolean(backgroundDataUri);
  const textColor = hasBackground ? '#FFFFFF' : '#2E2A24';
  const subTextColor = hasBackground ? 'rgba(255,255,255,0.75)' : '#6B6459';

  const contentChildren = [
    el(
      'div',
      {
        width: ICON_SIZE,
        height: ICON_SIZE,
        borderRadius: '50%',
        display: 'flex',
        overflow: 'hidden',
        backgroundColor: '#D8CCBB',
        marginBottom: ICON_NAME_GAP,
      },
      iconDataUri
        ? [img(iconDataUri, { width: '100%', height: '100%', objectFit: 'cover' })]
        : [],
    ),
    el(
      'div',
      {
        display: 'flex',
        fontSize: NAME_FONT_SIZE,
        fontWeight: 700,
        color: textColor,
        lineHeight: 1.2,
      },
      [name],
    ),
  ];

  if (description) {
    contentChildren.push(
      el(
        'div',
        { display: 'flex', fontSize: DESCRIPTION_FONT_SIZE, color: subTextColor },
        [description],
      ),
    );
  }

  for (const [index, link] of snsLinks.entries()) {
    contentChildren.push(
      el(
        'div',
        {
          display: 'flex',
          alignItems: 'center',
          marginTop: index === 0 ? SNS_LINKS_GAP : SNS_LINKS_GAP * 0.15,
          fontSize: SNS_FONT_SIZE,
          color: subTextColor,
        },
        [`🔗 ${link}`],
      ),
    );
  }

  const layers = [];
  if (backgroundDataUri) {
    layers.push(
      img(backgroundDataUri, {
        position: 'absolute',
        inset: 0,
        width: '100%',
        height: '100%',
        objectFit: 'cover',
      }),
    );
    layers.push(
      el('div', {
        position: 'absolute',
        inset: 0,
        display: 'flex',
        backgroundImage:
          'linear-gradient(to bottom, rgba(0,0,0,0) 40%, rgba(0,0,0,0.54) 100%)',
      }, []),
    );
  }
  layers.push(
    el(
      'div',
      {
        position: 'absolute',
        left: 0,
        right: 0,
        bottom: 0,
        display: 'flex',
        flexDirection: 'column',
        alignItems: 'flex-start',
        padding: CONTENT_PADDING,
      },
      contentChildren,
    ),
  );

  const root = el(
    'div',
    {
      width: '100%',
      height: '100%',
      display: 'flex',
      position: 'relative',
      backgroundColor: '#EFE7DC',
    },
    layers,
  );

  const response = new ImageResponse(root, {
    width: CARD_WIDTH,
    height: CARD_HEIGHT,
    fonts: fontData
      ? [{ name: 'Noto Sans JP', data: fontData, weight: 700, style: 'normal' }]
      : undefined,
  });
  // ImageResponseは既定でCache-Control: public, immutable, max-age=31536000
  // （1年間キャッシュ・再検証なし）を付ける。コンストラクタの`headers`
  // オプションで上書きを試みても、実際にはheaders.append()相当の挙動で
  // 既定値の後ろにカンマ結合されるだけで、既定の1年間キャッシュがそのまま
  // 有効になり続けていた（実機のcurlで
  // `cache-control: public, immutable, ..., max-age=31536000, public, max-age=300`
  // という二重値になっているのを確認して特定）。Vercelのエッジキャッシュは
  // 前者（1年）を採用してしまい、「カードを編集しても招待リンクの画像が
  // いつまでも更新されない」不具合になっていた。Response構築後に
  // `headers.set()`で明示的に上書きすることで、確実に単一の値に置き換える。
  return Buffer.from(await response.arrayBuffer());
}

// Vercel Functionのウォームインスタンスはしばらく（数分程度）使い回される
// ことがあり、その間はモジュールスコープの変数が保持される。同じアイコン・
// 背景画像URL（アップロードし直さない限り不変）・同じフォント文字列を
// 短時間に何度も取得しに行くのは無駄なので、インスタンスが生きている間だけ
// メモリ上にキャッシュする（Vercelのエッジ/ブラウザキャッシュのCache-Control
// とは別の、この関数の中だけで完結する軽量なキャッシュ）。エントリ数が
// 際限なく増えないよう上限を設けて古いものから捨てる。
const MAX_CACHE_ENTRIES = 50;
const pngCache = new Map();
const fontCache = new Map();

function rememberInCache(cache: Map<string, any>, key: string, value: any) {
  if (cache.size >= MAX_CACHE_ENTRIES) {
    const oldestKey = cache.keys().next().value;
    cache.delete(oldestKey as string);
  }
  cache.set(key, value);
}

async function toPngDataUri(url: string): Promise<string | null> {
  if (pngCache.has(url)) return pngCache.get(url);
  const res = await fetch(url);
  if (!res.ok) return null;
  const buffer = Buffer.from(await res.arrayBuffer());
  const png = await sharp(buffer).png().toBuffer();
  const dataUri = `data:image/png;base64,${png.toString('base64')}`;
  rememberInCache(pngCache, url, dataUri);
  return dataUri;
}

async function loadNotoSansJpCached(text: string) {
  if (fontCache.has(text)) return fontCache.get(text);
  const data = await loadNotoSansJp(text);
  rememberInCache(fontCache, text, data);
  return data;
}

async function fetchFirestoreDoc(path: string): Promise<any> {
  const url =
    `https://firestore.googleapis.com/v1/projects/${FIRESTORE_PROJECT_ID}` +
    `/databases/(default)/documents/${path}`;
  const res = await fetch(url);
  if (!res.ok) return null;
  const json: any = await res.json();
  return parseFirestoreFields(json.fields);
}

function parseFirestoreFields(fields: any) {
  if (!fields) return null;
  const result: Record<string, any> = {};
  for (const [key, value] of Object.entries(fields) as [string, any][]) {
    if ('stringValue' in value) result[key] = value.stringValue;
    else if ('nullValue' in value) result[key] = null;
    else if ('arrayValue' in value) {
      result[key] = (value.arrayValue.values || []).map((v: any) => v.stringValue);
    }
  }
  return result;
}

function parseSnsLinkUrls(value: any): string[] {
  if (!Array.isArray(value)) return [];
  return value.filter((v) => typeof v === 'string');
}

// カードに表示するURLはドメインのみの短い表示にする（アプリ内の
// プロフィールカード表示と同じ表示ルール、`lib/widgets/profile_card_view.dart`の
// `displaySnsLinkUrl()`参照。蔵の編集画面はフルパス表示のままだが、
// カード表示はドメインのみに短縮する方針のため、OGP画像もそれに合わせる
// 2026-09-25修正、以前は蔵用のフルパス表示ロジックのまま追従できていなかった）。
function displaySnsLinkUrl(link: string) {
  try {
    const host = new URL(link).hostname;
    return host.replace(/^www\./i, '');
  } catch {
    // パース出来ない値は従来通りscheme部分だけ除去するフォールバック。
    return link.replace(/^https?:\/\/(www\.)?/i, '');
  }
}

async function loadNotoSansJp(text: string) {
  const cssUrl = `https://fonts.googleapis.com/css2?family=Noto+Sans+JP:wght@700&text=${encodeURIComponent(text)}`;
  const cssRes = await fetch(cssUrl, {
    headers: {
      // TTF形式で返させるため、woff2非対応とみなされる古いUser-Agentを指定する
      // （@vercel/ogの公開サンプルで使われている定番の回避策）。
      'User-Agent':
        'Mozilla/5.0 (Windows NT 6.1; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/41.0.2228.0 Safari/537.36',
    },
  });
  if (!cssRes.ok) throw new Error('failed to fetch font css');
  const css = await cssRes.text();
  const match = css.match(/src: url\(([^)]+)\)/);
  if (!match) throw new Error('font url not found in css');
  const fontRes = await fetch(match[1]);
  if (!fontRes.ok) throw new Error('failed to fetch font file');
  return fontRes.arrayBuffer();
}

export async function renderOgImage(
  type: string | null,
  id: string | null,
): Promise<Buffer> {
  return render(type, id);
}
