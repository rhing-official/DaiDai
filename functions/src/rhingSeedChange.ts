/**
 * Rhing Seed変更（`changeRhingSeed`）の判定ロジック（2026-11-07）。
 * Firebase SDKに依存しない純粋関数にして、単体テストできるようにしてある
 * （自前化方針: 処理本体をFirebase固有のトリガー部分から分ける）。
 */

/** 変更できる間隔（日）。 */
export const SEED_CHANGE_INTERVAL_DAYS = 100;

/** 変更前のSeedを予約し、旧招待リンクを新Seedへ転送する期間（日）。 */
export const SEED_ALIAS_DAYS = 60;

const DAY_MS = 24 * 60 * 60 * 1000;

/** `lib/utils/reserved_rhing_seeds.dart`・`firestore.rules`と同じ一覧にすること。 */
export const RESERVED_RHING_SEEDS = ["tayori", "official", "daidai", "admin"];

const SEED_PATTERN = /^[a-z0-9._-]{1,20}$/;

export type SeedChangeError =
  | { code: "invalid-argument"; message: string }
  | { code: "already-exists"; message: string }
  | { code: "failed-precondition"; message: string };

export interface SeedChangeInput {
  /** 入力されたままの新Seed。 */
  newSeed: string;
  currentSeed: string;
  /** 最後に変更した時刻（ミリ秒）。一度も変更していなければnull。 */
  lastChangedAtMs: number | null;
  nowMs: number;
  /** 新Seedを別の住人が現在使っているか。 */
  takenByOther: boolean;
  /** 新Seedが別名（旧Seedの予約）として残っている場合のその持ち主と期限。 */
  alias: { uid: string; expiresAtMs: number } | null;
  uid: string;
}

/** 検証して、問題があればエラーを返す。問題が無ければ正規化済みの新Seedを返す。 */
export function evaluateSeedChange(
  input: SeedChangeInput,
): { ok: true; newSeed: string; restoringOwnAlias: boolean } | {
  ok: false;
  error: SeedChangeError;
} {
  const newSeed = input.newSeed.trim().toLowerCase();
  if (!SEED_PATTERN.test(newSeed)) {
    return {
      ok: false,
      error: {
        code: "invalid-argument",
        message: "Rhing Seedは英数字・.・-・_のみ、20文字以内で入力してください",
      },
    };
  }
  if (RESERVED_RHING_SEEDS.includes(newSeed)) {
    return {
      ok: false,
      error: { code: "already-exists", message: "このRhing Seedは使えません" },
    };
  }
  if (newSeed === input.currentSeed.toLowerCase()) {
    return {
      ok: false,
      error: {
        code: "invalid-argument",
        message: "現在のRhing Seedと同じです",
      },
    };
  }
  if (
    input.lastChangedAtMs !== null &&
    input.nowMs < input.lastChangedAtMs + SEED_CHANGE_INTERVAL_DAYS * DAY_MS
  ) {
    const remainingDays = Math.ceil(
      (input.lastChangedAtMs +
        SEED_CHANGE_INTERVAL_DAYS * DAY_MS -
        input.nowMs) /
        DAY_MS,
    );
    return {
      ok: false,
      error: {
        code: "failed-precondition",
        message: `Rhing Seedは${SEED_CHANGE_INTERVAL_DAYS}日に1回しか変更できません。あと${remainingDays}日お待ちください`,
      },
    };
  }
  if (input.takenByOther) {
    return {
      ok: false,
      error: {
        code: "already-exists",
        message: "このRhing Seedは既に使われています",
      },
    };
  }
  let restoringOwnAlias = false;
  if (input.alias && input.alias.expiresAtMs > input.nowMs) {
    if (input.alias.uid !== input.uid) {
      return {
        ok: false,
        error: {
          code: "already-exists",
          message: "このRhing Seedは既に使われています",
        },
      };
    }
    // 自分の旧Seedへ戻す場合は許可する（別名は削除する）。
    restoringOwnAlias = true;
  }
  return { ok: true, newSeed, restoringOwnAlias };
}

/** 別名（旧Seedの予約）の期限（ミリ秒）。 */
export function aliasExpiresAtMs(nowMs: number): number {
  return nowMs + SEED_ALIAS_DAYS * DAY_MS;
}
