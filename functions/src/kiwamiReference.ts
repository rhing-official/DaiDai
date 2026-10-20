/// 極みの決済リンクの`client_reference_id`（2026-10-20）。購入経路ごとに金額を変えるため、
/// アプリは`{uid}__{経路}`の形で付ける。経路が無い（従来の`{uid}`だけ）・知らない値の
/// ときは`standard`として扱う（既存の購入と後方互換）。

export const KIWAMI_CHANNELS = ["standard", "appStore", "googlePlay"] as const;
export type KiwamiChannel = (typeof KIWAMI_CHANNELS)[number];

const SEPARATOR = "__";

export function parseKiwamiReference(reference: string | null | undefined): {
  uid: string | null;
  channel: KiwamiChannel;
} {
  if (typeof reference !== "string" || reference.length === 0) {
    return { uid: null, channel: "standard" };
  }
  const index = reference.lastIndexOf(SEPARATOR);
  if (index < 0) return { uid: reference, channel: "standard" };
  const uid = reference.slice(0, index);
  const channel = reference.slice(index + SEPARATOR.length);
  if (uid.length === 0) return { uid: null, channel: "standard" };
  return {
    uid,
    channel: (KIWAMI_CHANNELS as readonly string[]).includes(channel)
      ? (channel as KiwamiChannel)
      : "standard",
  };
}
