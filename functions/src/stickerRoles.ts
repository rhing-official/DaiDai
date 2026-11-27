/// 公開済みのぺったんの役割を、後から付け直すときの入力の検証（2026-11-17）。
/// 画面・DBに依存しない部分だけを置く。

export interface StickerRoleUpdate {
  stickerId: string;
  roles: string[];
}

export type RoleUpdatesResult =
  | { ok: true; value: StickerRoleUpdate[] }
  | { ok: false; message: string };

/** 1回に更新できるぺったんの数の上限（1ぺったんの上限に十分足りる値）。 */
export const MAX_ROLE_UPDATES = 200;

/**
 * `[{ stickerId, roles }]`を検証して整える。stickerIdの重複は拒否し、rolesは
 * 空でない文字列だけにして、重複を除く。
 */
export function parseRoleUpdates(value: unknown): RoleUpdatesResult {
  if (!Array.isArray(value) || value.length === 0) {
    return { ok: false, message: "更新するぺったんが必要です" };
  }
  if (value.length > MAX_ROLE_UPDATES) {
    return { ok: false, message: `一度に更新できるのは${MAX_ROLE_UPDATES}枚までです` };
  }
  const seen = new Set<string>();
  const updates: StickerRoleUpdate[] = [];
  for (const item of value) {
    const entry = item as { stickerId?: unknown; roles?: unknown } | null;
    if (
      typeof entry !== "object" || entry === null ||
      typeof entry.stickerId !== "string" || !entry.stickerId ||
      !Array.isArray(entry.roles)
    ) {
      return { ok: false, message: "rolesの形式が正しくありません（stickerIdと、rolesの配列が必要）" };
    }
    if (seen.has(entry.stickerId)) {
      return { ok: false, message: `stickerId "${entry.stickerId}" が重複しています` };
    }
    seen.add(entry.stickerId);
    const roles = [
      ...new Set(
        entry.roles.filter((r): r is string => typeof r === "string" && r.trim() !== ""),
      ),
    ];
    updates.push({ stickerId: entry.stickerId, roles });
  }
  return { ok: true, value: updates };
}
