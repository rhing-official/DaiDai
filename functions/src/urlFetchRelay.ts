/**
 * リンクプレビュー用の取得中継（`urlFetchRelay`）の入力検証（2026-10-14）。
 * Cloudflare Workerからの取得が、pixiv・Instagramに（CloudflareのIP帯だと）
 * 弾かれるため、Google CloudのIPから取り直す。誰でも呼べる公開エンドポイントなので、
 * 取得先は許可リストのホストに限定する（オープンプロキシにしない）。
 */

const ALLOWED_HOSTS = new Set([
  "pixiv.net",
  "www.pixiv.net",
  "instagram.com",
  "www.instagram.com",
]);

/** 取得を許す`url`か。`https`・許可ホスト・標準ポート・認証情報なしのみ。 */
export function parseAllowedUrl(raw: unknown): URL | null {
  if (typeof raw !== "string" || raw.length > 2048) return null;
  let url: URL;
  try {
    url = new URL(raw);
  } catch {
    return null;
  }
  if (url.protocol !== "https:") return null;
  if (url.username || url.password) return null;
  if (url.port && url.port !== "443") return null;
  if (!ALLOWED_HOSTS.has(url.hostname.toLowerCase())) return null;
  return url;
}

/** 中継が名乗ってよいUA（任意の文字列を通さない）。 */
const ALLOWED_USER_AGENTS: Record<string, string> = {
  facebookexternalhit: "facebookexternalhit/1.1 (+http://www.facebook.com/externalhit_uatext.php)",
  twitterbot: "Twitterbot/1.0",
  discordbot: "Discordbot/2.0",
  mozilla: "Mozilla/5.0 (compatible; DaiDaiLinkPreview/1.0; +https://daidai.rhing.jp)",
};

export function resolveUserAgent(name: unknown): string {
  const key = typeof name === "string" ? name.toLowerCase() : "";
  return ALLOWED_USER_AGENTS[key] ?? ALLOWED_USER_AGENTS.facebookexternalhit;
}

/** Refererも許可ホストのオリジンだけ通す。 */
export function resolveReferer(raw: unknown): string | undefined {
  const url = parseAllowedUrl(raw);
  return url ? `${url.origin}/` : undefined;
}
