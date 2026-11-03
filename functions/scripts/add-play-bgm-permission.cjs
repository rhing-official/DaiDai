// 既存の広場の基準ロール（全員）に`playBgm`（通話にBGMを流す）を足す、一度きりの移行（2026-11-03）。
// 新しい広場は作成時に基準ロールへ含まれる（`GroupRepository.createGroup`）が、既存の広場には無いため、
// 足さないと長以外はBGMのボタンが出ない（初期値は「全員」というユーザー決定）。
//
// 使い方（functions ディレクトリで）:
//   node scripts/add-play-bgm-permission.cjs          … 変更の予定を表示するだけ（書き込まない）
//   node scripts/add-play-bgm-permission.cjs --apply  … 実際に書き込む
//
// やること: 各広場で、isEveryone=trueのロールのpermissionsへ`playBgm`を足し、広場の
// memberPermissions（全メンバー分の実効権限のキャッシュ）の各リストにも`playBgm`を足す。
// 既に含まれていれば何もしない（何度実行しても同じ）。
// 書き込みには`gcloud auth application-default login`（rhing.official@gmail.com）でのログインが必要。
const { initializeApp } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");

const PERMISSION = "playBgm";
const apply = process.argv.includes("--apply");

initializeApp({ projectId: "daidai-rhing" });
const db = getFirestore();

(async () => {
  const groups = await db.collection("groups").get();
  let changedGroups = 0;
  for (const groupDoc of groups.docs) {
    const roles = await groupDoc.ref.collection("roles").where("isEveryone", "==", true).get();
    const rolesToFix = roles.docs.filter((r) => !(r.data().permissions ?? []).includes(PERMISSION));
    const memberPermissions = groupDoc.data().memberPermissions ?? {};
    const membersToFix = Object.keys(memberPermissions).filter((uid) => !(memberPermissions[uid] ?? []).includes(PERMISSION));
    if (rolesToFix.length === 0 && membersToFix.length === 0) continue;
    changedGroups++;
    console.log(`${groupDoc.id}: 基準ロール ${rolesToFix.length}件、メンバーの実効権限 ${membersToFix.length}件`);
    if (!apply) continue;
    for (const role of rolesToFix) {
      await role.ref.update({ permissions: [...(role.data().permissions ?? []), PERMISSION] });
    }
    if (membersToFix.length > 0) {
      const updates = {};
      for (const uid of membersToFix) updates[`memberPermissions.${uid}`] = [...(memberPermissions[uid] ?? []), PERMISSION];
      await groupDoc.ref.update(updates);
    }
  }
  console.log(`${apply ? "更新" : "更新予定"}: ${changedGroups}/${groups.size}広場`);
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
