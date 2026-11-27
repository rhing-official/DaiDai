/**
 * アカウント削除で、意匠を全て削除する本体（2026-11-26）。Firebase の SDK に依存しない。
 * 規約第9条とプライバシーポリシーの「アカウント削除で、投稿した意匠は削除される」を実現する。
 * `index.ts` の `deleteAccount` が呼ぶ。途中で例外が出ると `users/{uid}` が残り、
 * `processAccountDeletions` が翌日に再実行するため、全ての段が冪等で、
 * 次の回の手がかりになる文書（投稿・公開意匠）は、その素材を消した後に消す。
 */

/** 文書を消す単位。Firestore の 500 件上限の内側 */
export const DELETE_CHUNK = 400;

export interface AccountDeletionStore {
  /** `themePackSubmissions` と `themePacks` の、`creatorId == uid` の packId（重複なし） */
  listCreatorPackIds(uid: string): Promise<string[]>;
  /** `ownedThemePacks` の、この packId の取得記録を、最大 `limit` 件消し、消した件数を返す */
  deleteOwnedRecords(packId: string, limit: number): Promise<number>;
  /** Storage の接頭辞（末尾は `/`）の下を全て消す。無くてもよい */
  deletePrefix(prefix: string): Promise<void>;
  deletePackDoc(packId: string): Promise<void>;
  /** `themePackSubmissions` の `creatorId == uid` の文書を、最大 `limit` 件消し、消した件数を返す */
  deleteSubmissionDocs(uid: string, limit: number): Promise<number>;
  /** 自分が取得した packId の一覧 */
  listOwnedPackIds(uid: string): Promise<string[]>;
  /** transaction で、`themePacks` が有れば `ownerCount` を1減らし（0未満にしない）、自分の取得記録を消す */
  releaseOwnedPack(uid: string, packId: string): Promise<void>;
  /** `users/{uid}/favoriteDesigns` の文書を、最大 `limit` 件消し、消した件数を返す（2026-11-27） */
  deleteFavoriteDesigns(uid: string, limit: number): Promise<number>;
  /** `users/{uid}/cartDesigns` の文書を、最大 `limit` 件消し、消した件数を返す（2026-11-27） */
  deleteCartDesigns(uid: string, limit: number): Promise<number>;
  /** 荒らし対策の記録（失敗の回数、運営による停止）を消す */
  deleteAbuseRecords(uid: string): Promise<void>;
}

async function drain(deleteChunk: () => Promise<number>): Promise<void> {
  for (;;) {
    const n = await deleteChunk();
    if (n < DELETE_CHUNK) return;
  }
}

/** この投稿者が作れる packId か。他人の素材・任意のパスを消さない為の確認 */
export function isCreatorPackId(uid: string, packId: string): boolean {
  return packId.startsWith(`${uid}__`) && !packId.includes("/") && !packId.includes("..");
}

export async function deleteThemePackData(store: AccountDeletionStore, uid: string): Promise<void> {
  if (!uid || uid.includes("/") || uid.includes("..")) {
    throw new Error("uidが正しくありません。");
  }

  // 1. 投稿者として。取得した人の記録 → 公開素材 → 公開文書 の順に消す
  const packIds = (await store.listCreatorPackIds(uid)).filter((id) => isCreatorPackId(uid, id));
  for (const packId of packIds) {
    await drain(() => store.deleteOwnedRecords(packId, DELETE_CHUNK));
    await store.deletePrefix(`themePacks/${packId}/`);
    await store.deletePackDoc(packId);
  }

  // 2. 提出の素材（提出されなかった物を含む）→ 提出の文書
  await store.deletePrefix(`themePackSubmissions/${uid}/`);
  await drain(() => store.deleteSubmissionDocs(uid, DELETE_CHUNK));

  // 3. 取得者として。投稿者の処理が先なので、自作の意匠は既に無い。そちらは減算せず、記録だけが消える
  for (const packId of await store.listOwnedPackIds(uid)) {
    await store.releaseOwnedPack(uid, packId);
  }

  // 4. 意匠のお気に入り・カート
  await drain(() => store.deleteFavoriteDesigns(uid, DELETE_CHUNK));
  await drain(() => store.deleteCartDesigns(uid, DELETE_CHUNK));

  // 5. 荒らし対策の記録
  await store.deleteAbuseRecords(uid);
}
