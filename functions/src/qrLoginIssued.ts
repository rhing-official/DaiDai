/**
 * ログイン済み端末がQRを表示し、ログインしたい端末が読み取る方式（2026-10-15）の
 * セッション状態遷移の判定。`qrLoginSessions/{id}`に`mode: 'issued'`・`ownerUid`を
 * 持たせ、pending → requested（読み取り）→ approved/denied（本人の許可）→
 * claimed（`claimQrLoginSession`）と進む。判定は純関数にして単体テストする。
 */

/** 発行したQRの有効期間（要求・許可まで）。ゲスト方式の3分より短くする。 */
export const ISSUED_QR_TTL_MS = 2 * 60 * 1000;

export interface IssuedSession {
  mode?: unknown;
  status?: unknown;
  ownerUid?: unknown;
  createdAtMs?: number;
}

export type IssuedCheck = { ok: true } | { ok: false; code: string; message: string };

function expired(session: IssuedSession, nowMs: number): boolean {
  return session.createdAtMs === undefined || nowMs - session.createdAtMs > ISSUED_QR_TTL_MS;
}

/** 読み取った端末が「ログインを要求」できるか（未ログインで呼ばれる）。 */
export function checkRequest(session: IssuedSession, nowMs: number): IssuedCheck {
  if (session.mode !== "issued") {
    return { ok: false, code: "failed-precondition", message: "このQRコードでは使えません" };
  }
  if (session.status !== "pending") {
    return { ok: false, code: "failed-precondition", message: "このQRコードは既に使用されています" };
  }
  if (expired(session, nowMs)) {
    return { ok: false, code: "deadline-exceeded", message: "QRコードの有効期限が切れています" };
  }
  return { ok: true };
}

/** ログイン済みの本人が、要求に「許可/拒否」を返せるか。 */
export function checkRespond(
  session: IssuedSession,
  callerUid: string,
  nowMs: number,
): IssuedCheck {
  if (session.mode !== "issued" || session.ownerUid !== callerUid) {
    return { ok: false, code: "permission-denied", message: "このセッションは操作できません" };
  }
  if (session.status !== "requested") {
    return { ok: false, code: "failed-precondition", message: "許可を待っている要求がありません" };
  }
  if (expired(session, nowMs)) {
    return { ok: false, code: "deadline-exceeded", message: "QRコードの有効期限が切れています" };
  }
  return { ok: true };
}
