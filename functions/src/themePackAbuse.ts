/**
 * 意匠パックの提出への荒らし対策（2026-11-26）。Firebase の SDK に依存しない。
 * - 1日の投稿回数の上限
 * - 提出の再検査に落ちる回数が続いた時の、一時停止
 * - 提出されないまま残った素材の掃除
 * トリガー側（`index.ts`）は、`Store` の実装と、スケジュールの登録だけを持つ。
 */

/** 24時間に提出できる回数。既存の「公開中と審査中で1人5件」とは別に数える */
export const DAILY_SUBMIT_LIMIT = 5;
export const DAILY_WINDOW_MS = 24 * 60 * 60 * 1000;

/** 再検査に落ちた回数。この時間の間に、この回数に達したら、最後に落ちた時から止める */
export const FAILURE_LIMIT = 10;
export const FAILURE_WINDOW_MS = 60 * 60 * 1000;
export const FAILURE_LOCK_MS = 60 * 60 * 1000;

/** 提出されなかった素材を残す時間。置いた直後の素材は、提出の前なので残す */
export const ORPHAN_AGE_MS = 24 * 60 * 60 * 1000;
/** 1回の掃除で消す単位（`{uid}/{submissionId}`）の上限。残りは次の回に回す */
export const ORPHAN_MAX_PER_RUN = 500;

export function isDailyLimitReached(countInWindow: number): boolean {
  return countInWindow >= DAILY_SUBMIT_LIMIT;
}

/** 失敗の時刻（ミリ秒）のうち、窓の中にある物だけを、古い順に最大 `FAILURE_LIMIT` 件残す */
export function recentFailures(failures: readonly number[], now: number): number[] {
  return failures
    .filter((t) => Number.isFinite(t) && t <= now && now - t < FAILURE_WINDOW_MS)
    .sort((a, b) => a - b)
    .slice(-FAILURE_LIMIT);
}

/**
 * 止めている間は、止める期限（ミリ秒）。止めていなければ null。
 * 「直近10回が、1時間以内に起きた」時に止め、期限は最後の失敗から1時間で固定する
 * （現在を基準に窓を滑らせると、止めている途中で古い失敗が窓から外れ、停止が早く切れてしまう）。
 */
export function failureLockedUntil(failures: readonly number[], now: number): number | null {
  const last = failures
    .filter((t) => Number.isFinite(t) && t <= now)
    .sort((a, b) => a - b)
    .slice(-FAILURE_LIMIT);
  if (last.length < FAILURE_LIMIT) return null;
  if (last[last.length - 1] - last[0] >= FAILURE_WINDOW_MS) return null;
  const until = last[last.length - 1] + FAILURE_LOCK_MS;
  return until > now ? until : null;
}

export interface AssetDir {
  /** `themePackSubmissions/{uid}/{submissionId}` */
  prefix: string;
  submissionId: string;
  /** その中で最も新しいファイルの作成時刻（ミリ秒） */
  newestMillis: number;
}

/** 掃除の対象: 最後の書き込みから `ORPHAN_AGE_MS` を過ぎ、同じ ID の提出文書が無い物 */
export function selectOrphanDirs(dirs: readonly AssetDir[], existingIds: ReadonlySet<string>, now: number): AssetDir[] {
  return dirs.filter((d) => now - d.newestMillis >= ORPHAN_AGE_MS && !existingIds.has(d.submissionId));
}

export interface OrphanCleanupStore {
  /** Storage の `themePackSubmissions/` の下を、`{uid}/{submissionId}` の単位に束ねて返す */
  listAssetDirs(): Promise<AssetDir[]>;
  /** 与えた ID のうち、`themePackSubmissions` に文書が有る物 */
  existingSubmissionIds(ids: string[]): Promise<Set<string>>;
  deleteDir(prefix: string): Promise<void>;
}

/** 消した単位の `prefix` を返す。1つの失敗で、残りを止めない */
export async function cleanupOrphanSubmissionAssets(
  store: OrphanCleanupStore,
  now: number,
  maxPerRun: number = ORPHAN_MAX_PER_RUN,
): Promise<{ deleted: string[]; failed: string[] }> {
  const dirs = (await store.listAssetDirs()).filter((d) => now - d.newestMillis >= ORPHAN_AGE_MS);
  const existing = await store.existingSubmissionIds([...new Set(dirs.map((d) => d.submissionId))]);
  const targets = selectOrphanDirs(dirs, existing, now).slice(0, maxPerRun);
  const deleted: string[] = [];
  const failed: string[] = [];
  for (const d of targets) {
    try {
      await store.deleteDir(d.prefix);
      deleted.push(d.prefix);
    } catch {
      failed.push(d.prefix);
    }
  }
  return { deleted, failed };
}
