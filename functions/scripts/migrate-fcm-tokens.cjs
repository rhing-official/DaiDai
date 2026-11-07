// FCMトークンを `users/{uid}.fcmTokens`（全ログイン者が読める）から
// `users/{uid}/private/fcm`（本人のみ）へ移す、一度きりの移行スクリプト（2026-11-07）。
//
// 使い方（DaiDaiリポジトリの functions ディレクトリで）:
//   node scripts/migrate-fcm-tokens.cjs            … ドライラン（何も書かず、件数だけ表示）
//   node scripts/migrate-fcm-tokens.cjs --apply    … 実際に移す（旧フィールドを削除）
//
// 実行順序: ①Cloud Functions（新旧両方を読む`loadFcmTokens`）をデプロイ →
// ②firestore.rulesをデプロイ → ③このスクリプトを--applyで実行 → ④新しいクライアントを
// リリース（旧クライアントのまま④より先に③を実行しても、旧クライアントは次回起動時に
// 旧フィールドへ再登録するため、④の後にもう一度実行して残りを移すこと）。
// 認証: `gcloud auth application-default login`（rhing.official@gmail.com）。
const { initializeApp } = require("firebase-admin/app");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");

const apply = process.argv.includes("--apply");
initializeApp({ projectId: "daidai-rhing" });
const db = getFirestore();

(async () => {
  const users = await db.collection("users").get();
  let withLegacy = 0;
  let moved = 0;
  for (const doc of users.docs) {
    const legacy = doc.data().fcmTokens;
    if (!Array.isArray(legacy)) continue;
    withLegacy++;
    if (!apply) continue;
    const ref = db.doc(`users/${doc.id}/private/fcm`);
    const current = (await ref.get()).data()?.tokens ?? [];
    const byToken = new Map();
    for (const e of [...current, ...legacy]) {
      if (e && typeof e.token === "string" && typeof e.platform === "string") {
        byToken.set(e.token, { token: e.token, platform: e.platform });
      }
    }
    await ref.set({ tokens: [...byToken.values()].slice(0, 10) });
    await doc.ref.update({ fcmTokens: FieldValue.delete() });
    moved++;
  }
  console.log(`users: ${users.size}, 旧fcmTokensあり: ${withLegacy}, 移行: ${moved}${apply ? "" : "（ドライラン）"}`);
})().catch((e) => { console.error(e); process.exit(1); });
