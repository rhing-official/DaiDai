// 招待リンク（/invite/:rhingId・/join/:groupId）のOGP画像を、アプリ内の
// プロフィールカード（工房カード・広場のプロフィールカード）とそのままの
// 見た目で生成するVercel Function（Node.js Runtime）。
// `api/link-preview.js`がog:imageとしてこのエンドポイント
// （/api/og-image?type=user&id=...・?type=group&id=...）を差し込む。
//
// アイコン・ニックネーム・URLだけを貼り付けたシンプルなog:imageと違い、
// 背景画像＋暗転グラデーション＋アイコン＋太字の名前＋説明（＋個人の場合は
// SNSのURL）を1枚の画像として合成する。レイアウトは
// `lib/features/profile/profile_tab.dart`の`_WorkshopCardSlot`・
// `lib/features/chat/group_profile_card_screen.dart`の見た目（背景全面＋
// 下から上へのグラデーション＋左下寄せの縦積みコンテンツ）を踏襲している。
//
// このプロジェクトにはNext.js等のフレームワーク・ビルド設定が無くJSXの
// トランスパイルを前提にできないため、@vercel/ogの要素ツリーはJSXを使わず
// Satoriが期待するプレーンなオブジェクト形（{type, props: {style, children}}）を
// 直接組み立てている（@vercel/og公式ドキュメントに記載のある非JSX環境向けの書き方）。
//
// 日本語を表示するため、@vercel/ogの既定フォント（欧文のみ）ではなく
// Google FontsからNoto Sans JPを実行時に取得して使う（CJK対応の
// @vercel/og公式サンプルで使われている定番の手法。TTF形式で取得するため、
// woff2非対応とみなされる古いUser-Agentを指定している）。
//
// 実機検証で判明した不具合と対応: 当初Edge Runtimeで実装していたが、実際の
// ユーザーデータ（アイコン・背景画像）を渡すと生成画像が中身0バイトのまま
// 壊れて返っていた。原因は、このアプリの画像保存形式がすべてWebP
// （`flutter_image_compress`でWebP圧縮する方針）である一方、@vercel/ogが
// 内部で使うSatori/resvgのレンダラーがWebP画像のデコードに対応しておらず、
// 画像取得後の描画中に失敗していたため（画像を持たないダミーIDでは正常に
// 生成できていたことから特定）。Edge Runtimeはネイティブモジュールを使えず
// WebPデコードを自前で行えないため、Node.js Runtime（configのruntime指定を
// 外すと既定でNode.jsになる）に変更し、`sharp`でWebP→PNGのdata URIに
// 変換してからSatoriに渡すようにして解消した。

import sharp from 'sharp';
import { ImageResponse } from '@vercel/og';

const FIRESTORE_PROJECT_ID = 'daidai-rhing';
const CARD_WIDTH = 800;
const CARD_HEIGHT = 1000;

function el(type, style, children) {
  return { type, props: { style, children } };
}

function img(src, style) {
  return { type: 'img', props: { src, style } };
}

// Node.js Runtimeでは`export default`は旧来の`(req, res) => void`シグネチャ専用で、
// Web標準のRequest/Responseを使う場合は`GET`等HTTPメソッド名の名前付きexportに
// する必要がある（実機検証で判明: `export default`のままだとレスポンスが
// 無視され、Vercelのハードタイムアウト=300秒までリクエストがハングし続けていた。
// Vercel側のワーニングログにもこの修正方法が明記されている）。
export async function GET(request) {
  // Edge Runtimeではrequest.urlが絶対URLだが、Node.js RuntimeではNode標準の
  // http.IncomingMessage.url同様パス+クエリのみになる（実機検証で判明:
  // `new URL(request.url)`が`ERR_INVALID_URL`で落ちていた）。どちらでも
  // 解析できるよう、ダミーのbaseを指定する（実際のオリジンとしては使わない）。
  const url = new URL(request.url, 'http://localhost');
  const type = url.searchParams.get('type');
  const id = url.searchParams.get('id');

  let doc = null;
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
  const [iconDataUri, backgroundDataUri] = await Promise.all([
    doc?.iconUrl ? toPngDataUri(doc.iconUrl).catch(() => null) : null,
    doc?.backgroundImageUrl
      ? toPngDataUri(doc.backgroundImageUrl).catch(() => null)
      : null,
  ]);
  const hasBackground = Boolean(backgroundDataUri);
  const textColor = hasBackground ? '#FFFFFF' : '#2E2A24';
  const subTextColor = hasBackground ? 'rgba(255,255,255,0.75)' : '#6B6459';

  const fontText = `${name}${description}${snsLinks.join('')}DaiDai`;
  let fontData;
  try {
    fontData = await loadNotoSansJp(fontText);
  } catch (e) {
    fontData = null;
  }

  const contentChildren = [
    el(
      'div',
      {
        width: 112,
        height: 112,
        borderRadius: '50%',
        display: 'flex',
        overflow: 'hidden',
        backgroundColor: '#D8CCBB',
        marginBottom: 28,
      },
      iconDataUri
        ? [img(iconDataUri, { width: '100%', height: '100%', objectFit: 'cover' })]
        : [],
    ),
    el(
      'div',
      { display: 'flex', fontSize: 56, fontWeight: 700, color: textColor, lineHeight: 1.2 },
      [name],
    ),
  ];

  if (description) {
    contentChildren.push(
      el(
        'div',
        { display: 'flex', fontSize: 32, marginTop: 12, color: subTextColor },
        [description],
      ),
    );
  }

  for (const link of snsLinks) {
    contentChildren.push(
      el(
        'div',
        { display: 'flex', alignItems: 'center', marginTop: 10, fontSize: 28, color: subTextColor },
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
        padding: 64,
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
  response.headers.set('Cache-Control', 'public, max-age=300');
  return response;
}

async function toPngDataUri(url) {
  const res = await fetch(url);
  if (!res.ok) return null;
  const buffer = Buffer.from(await res.arrayBuffer());
  const png = await sharp(buffer).png().toBuffer();
  return `data:image/png;base64,${png.toString('base64')}`;
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
    else if ('arrayValue' in value) {
      result[key] = (value.arrayValue.values || []).map((v) => v.stringValue);
    }
  }
  return result;
}

function parseSnsLinkUrls(value) {
  if (!Array.isArray(value)) return [];
  return value.filter((v) => typeof v === 'string');
}

// カードに表示するURLは`https://www.`部分を除いた短い表示にする
// （アプリ内のカード編集画面と同じ表示ルール、`lib/features/profile/profile_tab.dart`の
// `_displaySnsLinkUrl`参照）。
function displaySnsLinkUrl(link) {
  return link.replace(/^https?:\/\/(www\.)?/i, '');
}

async function loadNotoSansJp(text) {
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
