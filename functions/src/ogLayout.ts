// OGP画像（`ogImage.ts`）の、アイコン＋文字ブロックの配置を決める純関数
// （2026-10-12、工房カードの配置プリセット）。アプリ側の`CardLayoutPreset`/
// `CardTextAlign`（`lib/models/profile_card.dart`）と保存値（enumの`name`）を
// 共有する。未指定・不明な値は従来の左下・左揃え。

export type OgLayout = {
  // ブロックを置く縦位置と横位置（Satoriはflexのみ対応のため、絶対配置の
  // 全面コンテナ内で justify/align に落とす）
  justifyContent: "flex-start" | "center" | "flex-end"; // 縦（column方向）
  alignSelfX: "flex-start" | "center" | "flex-end"; // 横（ブロックの位置）
  // ブロック内で各行をどちらへ揃えるか
  itemsAlign: "flex-start" | "center" | "flex-end";
  textAlign: "left" | "center" | "right";
  // 暗幕のグラデーション（文字側を濃く）。centerは全面を一様に薄く。
  scrim: string;
};

const SCRIM_BOTTOM =
  "linear-gradient(to bottom, rgba(0,0,0,0) 40%, rgba(0,0,0,0.54) 100%)";
const SCRIM_TOP =
  "linear-gradient(to top, rgba(0,0,0,0) 40%, rgba(0,0,0,0.54) 100%)";
const SCRIM_FLAT = "linear-gradient(to bottom, rgba(0,0,0,0.38), rgba(0,0,0,0.38))";

export function resolveOgLayout(preset: unknown, align: unknown): OgLayout {
  let justifyContent: OgLayout["justifyContent"] = "flex-end";
  let alignSelfX: OgLayout["alignSelfX"] = "flex-start";
  let scrim = SCRIM_BOTTOM;
  switch (preset) {
    case "bottomCenter":
      alignSelfX = "center";
      break;
    case "bottomRight":
      alignSelfX = "flex-end";
      break;
    case "topLeft":
      justifyContent = "flex-start";
      scrim = SCRIM_TOP;
      break;
    case "topRight":
      justifyContent = "flex-start";
      alignSelfX = "flex-end";
      scrim = SCRIM_TOP;
      break;
    case "center":
      justifyContent = "center";
      alignSelfX = "center";
      scrim = SCRIM_FLAT;
      break;
    default:
      break; // bottomLeft・未指定・不明な値
  }
  let itemsAlign: OgLayout["itemsAlign"] = "flex-start";
  let textAlign: OgLayout["textAlign"] = "left";
  if (align === "center") {
    itemsAlign = "center";
    textAlign = "center";
  } else if (align === "end") {
    itemsAlign = "flex-end";
    textAlign = "right";
  }
  return { justifyContent, alignSelfX, itemsAlign, textAlign, scrim };
}
