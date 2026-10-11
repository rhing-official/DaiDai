/** 絶縁の提案通知の判定（2026-10-11追加）。Firestore非依存の純関数。 */

/** 同じ一対で通知を送り直すまでの最短間隔（提案→取り消しの連打対策）。 */
export const SEVERANCE_NOTIFY_COOLDOWN_MS = 60 * 60 * 1000;

export interface SeveranceDm {
  severanceRequestedBy?: unknown;
  participants?: unknown;
}

export interface SeveranceNotifyTarget {
  proposerId: string;
  recipientId: string;
}

/**
 * `severanceRequestedBy`が「別の値」から「userId」に変わった時だけ、通知先を返す
 * （取り消し・辞退・無関係な更新・同じ値のままならnull）。宛先は参加者のうち
 * 提案者でない1人。直近[SEVERANCE_NOTIFY_COOLDOWN_MS]以内に通知済みならnull。
 */
export function severanceNotifyTarget(
  before: SeveranceDm | undefined,
  after: SeveranceDm | undefined,
  lastNotifiedAtMs: number | null,
  nowMs: number,
): SeveranceNotifyTarget | null {
  const proposerId = after?.severanceRequestedBy;
  if (typeof proposerId !== "string" || proposerId.length === 0) return null;
  if (before?.severanceRequestedBy === proposerId) return null;
  if (
    lastNotifiedAtMs !== null &&
    nowMs - lastNotifiedAtMs < SEVERANCE_NOTIFY_COOLDOWN_MS
  ) {
    return null;
  }
  const participants = Array.isArray(after?.participants)
    ? (after!.participants as unknown[]).filter(
        (p): p is string => typeof p === "string",
      )
    : [];
  const recipientId = participants.find((p) => p !== proposerId);
  if (!recipientId) return null;
  return { proposerId, recipientId };
}
