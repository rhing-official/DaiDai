/**
 * 入力欄の下書きに添えたファイル（`draftFiles/{uid}/{conversationId}/{roomId}/{fileId}`、
 * 2026-11-27）の掃除。送信・取り外しで消えずに残ったものを、一定の日数が過ぎたら消す。
 * Firebase固有の部分（Storageの一覧・削除）は[DraftFileStore]に分け、判断だけをここに置く。
 */

/** 下書きのファイルを残す日数。 */
export const DRAFT_FILE_MAX_AGE_MS = 7 * 24 * 60 * 60 * 1000;

/** 1回の掃除で消す数の上限。残りは翌日に回す。 */
export const DRAFT_FILE_DELETE_LIMIT = 1000;

export type DraftFileEntry = { name: string; createdMillis: number };

export interface DraftFileStore {
  list(): Promise<DraftFileEntry[]>;
  delete(name: string): Promise<void>;
}

/** 古い順に、期限切れのファイルを選ぶ（作成時刻が不明のものは消さない）。 */
export function selectExpiredDraftFiles(
  entries: DraftFileEntry[],
  nowMs: number,
  maxAgeMs: number = DRAFT_FILE_MAX_AGE_MS,
  limit: number = DRAFT_FILE_DELETE_LIMIT,
): string[] {
  return entries
    .filter((e) => Number.isFinite(e.createdMillis) && nowMs - e.createdMillis > maxAgeMs)
    .sort((a, b) => a.createdMillis - b.createdMillis)
    .slice(0, limit)
    .map((e) => e.name);
}

export async function cleanupExpiredDraftFiles(
  store: DraftFileStore,
  nowMs: number,
): Promise<{ deleted: string[]; failed: string[] }> {
  const expired = selectExpiredDraftFiles(await store.list(), nowMs);
  const deleted: string[] = [];
  const failed: string[] = [];
  for (const name of expired) {
    try {
      await store.delete(name);
      deleted.push(name);
    } catch {
      failed.push(name);
    }
  }
  return { deleted, failed };
}
