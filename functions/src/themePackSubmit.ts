/**
 * 素材パックの提出（`submitThemePack`）の本体（2026-11-26）。Firebase の SDK に依存しない。
 * トリガー側（`index.ts`）は、`SubmissionStore` の実装と、`SubmitError` から `HttpsError` への変換だけを持つ。
 * 自前化の時に、この本体だけを別サーバーへ移せるようにする（`CLAUDE.md` の方針）。
 */
import { THEME_PACK_LIMITS, validateThemePackFiles, type ThemePackBrightness } from "./themePack";

export type SubmitErrorCode =
  | "unauthenticated"
  | "invalid-argument"
  | "permission-denied"
  | "resource-exhausted";

/** 投稿者へそのまま見せてよい日本語の理由を持つ */
export class SubmitError extends Error {
  constructor(
    readonly code: SubmitErrorCode,
    message: string,
  ) {
    super(message);
  }
}

/** 投稿の状態のうち、1人5件の上限に数えるもの */
export const ACTIVE_STATUSES = ["submitted", "inReview", "approved"] as const;

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const ALLOWED_CONTENT_TYPES = new Set(["application/json", "image/png", "image/webp", "image/jpeg"]);

export interface StoredFile {
  /** フォルダを含まないファイル名 */
  name: string;
  size: number;
  contentType: string | undefined;
}

export interface SubmissionRecord {
  creatorId: string;
  packId: string;
  version: number;
}

/** 文書の書き込みの窓口。1回の transaction の中で使う */
export interface SubmissionTx {
  getSubmission(submissionId: string): Promise<SubmissionRecord | null>;
  /** `creatorId` の投稿のうち、`ACTIVE_STATUSES` の件数 */
  countActive(creatorId: string): Promise<number>;
  /** 同じ `packId` の既存の投稿の最大の版。無ければ 0 */
  maxVersion(packId: string): Promise<number>;
  create(
    submissionId: string,
    record: SubmissionRecord & { assetPath: string; name: string; brightness: ThemePackBrightness },
  ): void;
}

export interface SubmissionStore {
  listFiles(prefix: string): Promise<StoredFile[]>;
  readFile(prefix: string, name: string): Promise<Uint8Array>;
  runTransaction<T>(fn: (tx: SubmissionTx) => Promise<T>): Promise<T>;
}

export interface SubmitInput {
  uid: string | undefined;
  data: unknown;
}

export interface SubmitResult {
  submissionId: string;
  packId: string;
  version: number;
}

/** 提出先の保存先のパス（接頭辞）。Firestore にも、この文字列を持つ */
export function submissionAssetPath(uid: string, submissionId: string): string {
  return `themePackSubmissions/${uid}/${submissionId}`;
}

export function themePackId(creatorId: string, packJsonId: string): string {
  return `${creatorId}__${packJsonId}`;
}

export async function submitThemePack(store: SubmissionStore, input: SubmitInput): Promise<SubmitResult> {
  const { uid } = input;
  if (!uid) throw new SubmitError("unauthenticated", "ログインが必要です。");

  const data = (input.data ?? {}) as { submissionId?: unknown; rightsAccepted?: unknown };
  const submissionId = data.submissionId;
  if (typeof submissionId !== "string" || !UUID_PATTERN.test(submissionId)) {
    throw new SubmitError("invalid-argument", "submissionIdが正しくありません。");
  }
  if (data.rightsAccepted !== true) {
    throw new SubmitError("invalid-argument", "権利の表明への同意が必要です。");
  }

  // 同じ submissionId の再送は、二重に作らず、作成済みの結果を返す。他人のものは拒否する
  const existing = await store.runTransaction((tx) => tx.getSubmission(submissionId));
  if (existing) return resultOf(uid, submissionId, existing);

  const prefix = submissionAssetPath(uid, submissionId);
  const listed = await store.listFiles(prefix);
  if (listed.length === 0) {
    throw new SubmitError("invalid-argument", "送られたファイルが見つかりません。もう一度送り直してください。");
  }
  if (listed.length > THEME_PACK_LIMITS.maxFiles) {
    throw new SubmitError("invalid-argument", `ファイルが多すぎます。${THEME_PACK_LIMITS.maxFiles}個以下にしてください。`);
  }
  // 読む前に、サイズと種類を見る（大きなファイルをメモリへ読まない）
  for (const f of listed) {
    if (f.size > THEME_PACK_LIMITS.imageMaxBytes) {
      throw new SubmitError("invalid-argument", `「${f.name}」の容量が大きすぎます。`);
    }
    if (!f.contentType || !ALLOWED_CONTENT_TYPES.has(f.contentType)) {
      throw new SubmitError("invalid-argument", `「${f.name}」は、使えない種類のファイルです。`);
    }
  }
  const files = new Map<string, Uint8Array>();
  for (const f of listed) files.set(f.name, await store.readFile(prefix, f.name));

  const checked = validateThemePackFiles(files);
  if (!checked.ok) {
    throw new SubmitError("invalid-argument", `意匠パックを受け付けられません。${checked.errors.join("")}`);
  }

  const packId = themePackId(uid, checked.pack.id);
  const created = await store.runTransaction(async (tx): Promise<SubmissionRecord> => {
    // 並行した再送への備えとして、transaction の中でも確かめる
    const again = await tx.getSubmission(submissionId);
    if (again) return again;
    if ((await tx.countActive(uid)) >= THEME_PACK_LIMITS.maxPacksPerUser) {
      throw new SubmitError("resource-exhausted", "投稿できる数の上限に達しています。");
    }
    const version = (await tx.maxVersion(packId)) + 1;
    tx.create(submissionId, {
      creatorId: uid,
      packId,
      version,
      assetPath: prefix,
      name: checked.pack.name,
      brightness: checked.pack.brightness,
    });
    return { creatorId: uid, packId, version };
  });
  return resultOf(uid, submissionId, created);
}

function resultOf(uid: string, submissionId: string, record: SubmissionRecord): SubmitResult {
  if (record.creatorId !== uid) {
    throw new SubmitError("permission-denied", "このsubmissionIdは使えません。");
  }
  return { submissionId, packId: record.packId, version: record.version };
}
