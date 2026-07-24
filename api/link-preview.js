// 招待リンク（/invite/:rhingId）・広場の招待リンク（/join/:groupId）用の
// OGP（外部SNS等でリンクを貼った時のリッチカード表示）対応。
//
// Flutter Webはビルドすると静的なindex.html 1枚で全ルートを描画するSPAになる
// ため、クローラー（Discord/LINE/X等のリンク展開ボット）はog:title等の
// メタタグを個別URLごとに動的化できない。この関数がvercel.jsonのrewritesで
// /invite/:rhingId・/join/:groupId宛のリクエストを肩代わりし、Firestoreの
// 公開プレビュー（userInvites/groupInvites、いずれもセキュリティルールで
// 誰でも読み取り可能）から取得した内容でog:*タグだけを差し込んだindex.htmlを
// 返す。中身（bootstrapスクリプト等）は本物のindex.htmlをそのまま流用するため、
// 実際にリンクを開いた人（ブラウザでJSを実行する側）には通常通りDaiDaiの
// アプリ本体が起動する。
//
// 未検証: ローカルでは実際のクローラー展開・Vercelデプロイを通した動作確認が
// できないため、デプロイ後にDiscord/LINE/X等の実機・プレビューツールでの
// 確認が別途必要。

const FIRESTORE_PROJECT_ID = 'daidai-rhing';

module.exports = async (req, res) => {
  const host = req.headers.host;
  const url = new URL(req.url, `https://${host}`);
  const inviteMatch = url.pathname.match(/^\/invite\/([^/]+)\/?$/);
  const joinMatch = url.pathname.match(/^\/join\/([^/]+)\/?$/);

  let title = 'DaiDai';
  let description = '整う、守る、私に馴染む。DaiDai';
  let image = null;

  try {
    if (inviteMatch) {
      const rhingId = decodeURIComponent(inviteMatch[1]);
      const doc = await fetchFirestoreDoc(`userInvites/${rhingId}`);
      if (doc) {
        title = doc.nickname ? `${doc.nickname}（@${rhingId}）` : `@${rhingId}`;
        description = 'DaiDaiで仲間になりましょう';
        image = doc.iconUrl || null;
      }
    } else if (joinMatch) {
      const groupId = decodeURIComponent(joinMatch[1]);
      const doc = await fetchFirestoreDoc(`groupInvites/${groupId}`);
      if (doc) {
        title = doc.name || title;
        description = doc.description || 'DaiDaiの広場に参加しましょう';
        image = doc.iconUrl || null;
      }
    }
  } catch (e) {
    // Firestore取得に失敗しても、既定のOGタグでページ自体は返す
    // （リンク自体が開けなくなることは避ける）。
  }

  let html;
  try {
    const indexRes = await fetch(`https://${host}/index.html`);
    html = await indexRes.text();
  } catch (e) {
    res.status(502).send('index.html not available');
    return;
  }

  const ogTags = [
    `<meta property="og:title" content="${escapeHtml(title)}">`,
    `<meta property="og:description" content="${escapeHtml(description)}">`,
    `<meta property="og:url" content="${escapeHtml(url.toString())}">`,
    image ? `<meta property="og:image" content="${escapeHtml(image)}">` : '',
    `<meta name="twitter:card" content="${image ? 'summary_large_image' : 'summary'}">`,
  ].filter(Boolean).join('\n    ');

  html = html.replace('</head>', `    ${ogTags}\n  </head>`);

  res.setHeader('Content-Type', 'text/html; charset=utf-8');
  res.status(200).send(html);
};

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
