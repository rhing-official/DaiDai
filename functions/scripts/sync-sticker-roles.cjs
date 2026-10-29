// functions/data/sticker-roles.json の内容を、Firestore（daidai-rhing）の stickerRoles に反映する。
//
// 使い方（DaiDaiリポジトリの functions ディレクトリで）:
//   node scripts/sync-sticker-roles.cjs           … 検証して、内容を表示する。Googleのログインがあれば、Firestoreとの差分も表示（書き込まない）
//   node scripts/sync-sticker-roles.cjs --apply   … 検証に通ったら、stickerRoles に書き込む（JSONに無い役割は消さない）
//
// 書き込みには、`gcloud auth application-default login` でのログインが必要。
const fs = require("fs");
const path = require("path");

const DATA_PATH = path.join(__dirname, "..", "data", "sticker-roles.json");
const apply = process.argv.includes("--apply");

function load(filePath) {
  const parsed = JSON.parse(fs.readFileSync(filePath, "utf8"));
  if (!parsed || !Array.isArray(parsed.roles)) throw new Error('JSONに "roles" の配列がありません');
  return parsed.roles;
}

// 検証。問題があれば、メッセージの配列を返す（空なら問題なし）
function validate(roles) {
  const errors = [];
  const ids = new Set();
  roles.forEach((r, i) => {
    const label = `roles[${i}]${r && r.roleId ? `（${r.roleId}）` : ""}`;
    if (!r || typeof r.roleId !== "string" || !/^[a-z][a-z0-9_]*$/.test(r.roleId)) {
      errors.push(`${label}: roleIdは、英小文字で始まる英数字と_だけにしてください`);
      return;
    }
    if (ids.has(r.roleId)) errors.push(`${label}: roleIdが重複しています`);
    ids.add(r.roleId);
    if (typeof r.name !== "string" || !r.name.trim()) errors.push(`${label}: nameが空です`);
    if (!Array.isArray(r.keywords) || r.keywords.length === 0) {
      errors.push(`${label}: keywordsが空です`);
      return;
    }
    const seen = new Set();
    for (const k of r.keywords) {
      if (typeof k !== "string" || !k.trim()) errors.push(`${label}: 空のキーワードがあります`);
      else if (k !== k.trim()) errors.push(`${label}: 前後に空白のあるキーワードがあります（"${k}"）`);
      else if (seen.has(k)) errors.push(`${label}: キーワードが重複しています（"${k}"）`);
      else seen.add(k);
    }
  });
  return errors;
}

module.exports = { validate, load };

if (require.main === module) {
  (async () => {
    const roles = load(DATA_PATH);
    const errors = validate(roles);
    if (errors.length > 0) {
      console.error("JSONに問題があります:");
      errors.forEach((e) => console.error(`  - ${e}`));
      process.exit(1);
    }

    console.log(`役割: ${roles.length}件（検証OK）`);
    for (const r of roles) console.log(`  ${r.roleId.padEnd(10)} ${r.name}  [${r.keywords.join(", ")}]`);

    // Firestoreの現状と比べる（ログインが無ければ、比較できないので飛ばす）
    const { initializeApp } = require("firebase-admin/app");
    const { getFirestore } = require("firebase-admin/firestore");
    initializeApp({ projectId: "daidai-rhing" });
    const db = getFirestore();

    let current = null;
    try {
      const snapshot = await db.collection("stickerRoles").get();
      current = new Map(snapshot.docs.map((d) => [d.id, d.data()]));
    } catch (e) {
      if (apply) throw e;
      console.log("\n（Firestoreの現状は読めませんでした。比較には、gcloud auth application-default login が必要です）");
    }

    if (current) {
      console.log("\nFirestoreとの差分:");
      let changed = 0;
      for (const r of roles) {
        const cur = current.get(r.roleId);
        if (!cur) {
          console.log(`  + 新しい役割 ${r.roleId}（${r.name}）: ${r.keywords.join(", ")}`);
          changed++;
          continue;
        }
        const curKeywords = Array.isArray(cur.keywords) ? cur.keywords : [];
        const added = r.keywords.filter((k) => !curKeywords.includes(k));
        const removed = curKeywords.filter((k) => !r.keywords.includes(k));
        const renamed = cur.name !== r.name;
        if (added.length || removed.length || renamed) {
          changed++;
          console.log(`  * ${r.roleId}（${r.name}）${renamed ? `  名前: ${cur.name} → ${r.name}` : ""}`);
          if (added.length) console.log(`      追加: ${added.join(", ")}`);
          if (removed.length) console.log(`      削除: ${removed.join(", ")}`);
        }
      }
      const orphan = [...current.keys()].filter((id) => !roles.some((r) => r.roleId === id));
      if (orphan.length) console.log(`  （JSONに無い役割は、そのまま残します: ${orphan.join(", ")}）`);
      if (changed === 0) console.log("  差分なし");
    }

    if (!apply) {
      console.log("\n（書き込んでいません。--apply を付けると、daidai-rhingのFirestoreに書き込みます）");
      process.exit(0);
    }

    const batch = db.batch();
    for (const r of roles) batch.set(db.collection("stickerRoles").doc(r.roleId), { name: r.name, keywords: r.keywords });
    await batch.commit();
    console.log(`\n完了: stickerRolesに${roles.length}件を書き込みました（アプリの更新は不要です）`);
    process.exit(0);
  })().catch((e) => {
    console.error("失敗:", e.message);
    process.exit(1);
  });
}
