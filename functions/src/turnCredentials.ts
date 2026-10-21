/// Cloudflare Realtime TURNが返す`iceServers`を、クライアントへ渡せる形に整える
/// （2026-10-21）。ブラウザが塞いでいるポート53のURLは、接続の確立に時間がかかる
/// 原因になるので外す。形が想定と違うものは捨てる（クライアントには、必要な
/// `urls`・`username`・`credential`だけを渡す）。

export type IceServer = {
  urls: string[];
  username?: string;
  credential?: string;
};

function isPort53(url: string): boolean {
  return /:53(\?|$)/.test(url);
}

export function filterTurnIceServers(raw: unknown): IceServer[] {
  if (!Array.isArray(raw)) return [];
  const result: IceServer[] = [];
  for (const entry of raw) {
    if (typeof entry !== "object" || entry === null) continue;
    const { urls, username, credential } = entry as Record<string, unknown>;
    const list = (Array.isArray(urls) ? urls : [urls]).filter(
      (u): u is string => typeof u === "string" && !isPort53(u),
    );
    if (list.length === 0) continue;
    const server: IceServer = { urls: list };
    if (typeof username === "string") server.username = username;
    if (typeof credential === "string") server.credential = credential;
    result.push(server);
  }
  return result;
}
