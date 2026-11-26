/**
 * 意匠パックの取得・アンインストール・取り下げの本体（2026-11-26）。Firebase の SDK に依存しない。
 * トリガー側（`index.ts`）は、`OwnershipStore` の実装と、`OwnershipError` から `HttpsError` への変換だけを持つ。
 * 自前化の時に、この本体だけを別サーバーへ移せるようにする（`CLAUDE.md` の方針）。
 * ぺったんの `grantOwnership`・`uninstallStickerPack` に倣うが、コレクションは混ぜず、別に持つ。
 */

export type OwnershipErrorCode =
  | "unauthenticated"
  | "invalid-argument"
  | "not-found"
  | "failed-precondition"
  | "permission-denied";

/** 利用者へそのまま見せてよい日本語の理由を持つ */
export class OwnershipError extends Error {
  constructor(
    readonly code: OwnershipErrorCode,
    message: string,
  ) {
    super(message);
  }
}

export const PAID_THEME_PACKS_DISABLED_MESSAGE =
  "現在、有料の意匠パックには対応していません。無料の意匠パックのみご利用いただけます。";

export interface OwnedPack {
  creatorId: string;
  version: number;
  status: string;
  /** 未設定・数値でないものは 0（無料）として扱う */
  price: number;
  ownerCount: number;
}

/** 1回の transaction の中で使う窓口。読み取りを全て済ませてから、書き込みを呼ぶ */
export interface OwnershipTx {
  getPack(packId: string): Promise<OwnedPack | null>;
  hasOwned(uid: string, packId: string): Promise<boolean>;
  /** 同じ `packId` と `version` の投稿。1件のはず */
  findSubmission(packId: string, version: number): Promise<{ id: string; status: string } | null>;
  /** `{ packId, grantedAt, version }` を作る */
  setOwned(uid: string, packId: string, version: number): void;
  deleteOwned(uid: string, packId: string): void;
  setOwnerCount(packId: string, count: number): void;
  setPackStatus(packId: string, status: "withdrawn"): void;
  setSubmissionStatus(submissionId: string, status: "withdrawn"): void;
}

export interface OwnershipStore {
  runTransaction<T>(fn: (tx: OwnershipTx) => Promise<T>): Promise<T>;
}

export interface OwnershipInput {
  uid: string | undefined;
  data: unknown;
}

function requireUid(uid: string | undefined): string {
  if (!uid) throw new OwnershipError("unauthenticated", "ログインが必要です。");
  return uid;
}

function readPackId(data: unknown): string {
  const v = (data as Record<string, unknown> | null | undefined)?.packId;
  if (typeof v !== "string" || !v) throw new OwnershipError("invalid-argument", "packIdが必要です。");
  return v;
}

// ---------------------------------------------------------------------------
// 取得
// ---------------------------------------------------------------------------

export interface AcquireResult {
  packId: string;
  version: number;
  alreadyOwned: boolean;
}

export interface AcquireOptions {
  /** `PAID_PACKS_ENABLED` と同じ値。false の間は、有料を拒否する */
  paidPacksEnabled: boolean;
}

export async function acquireThemePack(
  store: OwnershipStore,
  input: OwnershipInput,
  options: AcquireOptions,
): Promise<AcquireResult> {
  const uid = requireUid(input.uid);
  const packId = readPackId(input.data);

  return store.runTransaction(async (tx) => {
    // 読み取りを先に済ませる（transaction の作法）
    const pack = await tx.getPack(packId);
    const owned = await tx.hasOwned(uid, packId);
    if (!pack) throw new OwnershipError("not-found", "意匠パックが見つかりません。");

    // 既に持っている人の二重呼び出しは、状態や価格に関わらず、何も変えずに成功とする
    if (owned) return { packId, version: pack.version, alreadyOwned: true };

    if (pack.status !== "approved") {
      throw new OwnershipError("failed-precondition", "この意匠パックは、現在、取得できません。");
    }
    if (pack.price > 0 && !options.paidPacksEnabled) {
      throw new OwnershipError("failed-precondition", PAID_THEME_PACKS_DISABLED_MESSAGE);
    }

    // 取得した時点の版を記録する。公開中の版が後で上がっても、自動では変えない
    tx.setOwned(uid, packId, pack.version);
    tx.setOwnerCount(packId, pack.ownerCount + 1);
    return { packId, version: pack.version, alreadyOwned: false };
  });
}

// ---------------------------------------------------------------------------
// アンインストール
// ---------------------------------------------------------------------------

export interface UninstallResult {
  packId: string;
  /** 今回の呼び出しで、記録を外した（記録が無かった時は false） */
  removed: boolean;
}

/** 状態（取り下げ・停止）に関わらず、取得した人は、いつでも外せる */
export async function uninstallThemePack(
  store: OwnershipStore,
  input: OwnershipInput,
): Promise<UninstallResult> {
  const uid = requireUid(input.uid);
  const packId = readPackId(input.data);

  return store.runTransaction(async (tx) => {
    const owned = await tx.hasOwned(uid, packId);
    const pack = await tx.getPack(packId);
    if (!owned) return { packId, removed: false };

    tx.deleteOwned(uid, packId);
    // 0 未満にしない。パックが既に無くても、記録は外せる
    if (pack) tx.setOwnerCount(packId, Math.max(0, pack.ownerCount - 1));
    return { packId, removed: true };
  });
}

// ---------------------------------------------------------------------------
// 取り下げ
// ---------------------------------------------------------------------------

export interface WithdrawResult {
  packId: string;
  status: "withdrawn";
  /** 今回の呼び出しで、状態を変えた（二重の呼び出しでは false） */
  changed: boolean;
}

/**
 * 投稿者本人が、公開中の意匠パックを取り下げる。新規の取得だけを止める。
 * 取得した人の記録（`ownedThemePacks`）・公開用の素材・`ownerCount` には触れない。
 * 取得した人へのお知らせは送らない。再公開は、新しい版の投稿から行う。
 */
export async function withdrawThemePack(
  store: OwnershipStore,
  input: OwnershipInput,
): Promise<WithdrawResult> {
  const uid = requireUid(input.uid);
  const packId = readPackId(input.data);

  return store.runTransaction(async (tx) => {
    const pack = await tx.getPack(packId);
    if (!pack) throw new OwnershipError("not-found", "意匠パックが見つかりません。");
    if (pack.creatorId !== uid) {
      throw new OwnershipError("permission-denied", "自分の意匠パックだけを取り下げられます。");
    }
    if (pack.status === "withdrawn") return { packId, status: "withdrawn" as const, changed: false };
    if (pack.status !== "approved") {
      throw new OwnershipError("failed-precondition", "公開中の意匠パックだけを取り下げられます。");
    }
    const sub = await tx.findSubmission(packId, pack.version);

    tx.setPackStatus(packId, "withdrawn");
    if (sub) tx.setSubmissionStatus(sub.id, "withdrawn");
    return { packId, status: "withdrawn" as const, changed: true };
  });
}
