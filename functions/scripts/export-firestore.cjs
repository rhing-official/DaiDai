// Firestore（daidai-rhing）の全データを、ローカルのJSONL（1行1ドキュメント）に書き出す。
// 自前化（`文書/自前化計画.md`）へ備えた、移行用のバックアップ兼リハーサル。読み取りだけで、書き込みはしない。
//
// 使い方（DaiDaiリポジトリの functions ディレクトリで）:
//   node scripts/export-firestore.cjs                    … 全コレクションを backups/firestore-<日時>/ へ書き出す
//   node scripts/export-firestore.cjs --out <ディレクトリ>  … 書き出し先を指定
//   node scripts/export-firestore.cjs --only users,groups  … 指定したトップレベルのコレクションだけ
//   node scripts/export-firestore.cjs --count             … 書き出さず、コレクションごとの件数だけ数える
//
// 読み取りには、`gcloud auth application-default login`（rhing.official@gmail.com）でのログインが必要。
// 出力にはパスワードの代わりの秘密の質問のハッシュ・FCMトークン等の機微な値が含まれる。
// 外へ出さない（Git・クラウドに置かない）。`functions/backups/`は.gitignore済み。
//
// 形式: コレクションのトップレベルごとに <名前>.jsonl。各行は {"path":"users/uid/profiles/x","data":{...}}。
// Firestoreの型は {"__type":"timestamp","seconds":N,"nanos":N}／geopoint／reference／bytes（base64）で保つ。
const fs = require("fs");
const path = require("path");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore, Timestamp, GeoPoint, DocumentReference, FieldPath } = require("firebase-admin/firestore");

const args = process.argv.slice(2);
const flag = (name) => args.includes(name);
const option = (name) => {
  const i = args.indexOf(name);
  return i >= 0 ? args[i + 1] : undefined;
};

const countOnly = flag("--count");
const only = option("--only")?.split(",").map((s) => s.trim()).filter(Boolean);
const stamp = new Date().toISOString().replace(/[:.]/g, "-");
const outDir = path.resolve(option("--out") ?? path.join(__dirname, "..", "backups", `firestore-${stamp}`));

initializeApp({ projectId: "daidai-rhing" });
const db = getFirestore();

// Firestoreの値を、型が分かるJSONへ変換する。
function encode(value) {
  if (value === null || value === undefined) return null;
  if (value instanceof Timestamp) return { __type: "timestamp", seconds: value.seconds, nanos: value.nanoseconds };
  if (value instanceof GeoPoint) return { __type: "geopoint", latitude: value.latitude, longitude: value.longitude };
  if (value instanceof DocumentReference) return { __type: "reference", path: value.path };
  if (Buffer.isBuffer(value) || value instanceof Uint8Array) {
    return { __type: "bytes", base64: Buffer.from(value).toString("base64") };
  }
  if (Array.isArray(value)) return value.map(encode);
  if (typeof value === "object") {
    const result = {};
    for (const [k, v] of Object.entries(value)) result[k] = encode(v);
    return result;
  }
  return value;
}

const counts = {};

// コレクション（とそのサブコレクション）を再帰して、各ドキュメントを書き出す。
async function walk(collection, rootName, stream) {
  // 大きなコレクションでもメモリを使い切らないよう、ドキュメントIDの順に分割して読む。
  let last;
  for (;;) {
    let query = collection.orderBy(FieldPath.documentId()).limit(500);
    if (last) query = query.startAfter(last);
    const snapshot = await query.get();
    if (snapshot.empty) break;
    for (const doc of snapshot.docs) {
      counts[rootName] = (counts[rootName] ?? 0) + 1;
      if (stream) stream.write(JSON.stringify({ path: doc.ref.path, data: encode(doc.data()) }) + "\n");
    }
    // サブコレクションの一覧と中身は、ドキュメントごとに待たず、まとめて並行して読む（速くするため）。
    await Promise.all(
      snapshot.docs.map(async (doc) => {
        for (const sub of await doc.ref.listCollections()) await walk(sub, rootName, stream);
      }),
    );
    last = snapshot.docs[snapshot.docs.length - 1];
    if (snapshot.size < 500) break;
  }
}

async function main() {
  const roots = (await db.listCollections()).filter((c) => !only || only.includes(c.id));
  if (!countOnly) fs.mkdirSync(outDir, { recursive: true });
  for (const root of roots) {
    const stream = countOnly ? null : fs.createWriteStream(path.join(outDir, `${root.id}.jsonl`));
    await walk(root, root.id, stream);
    if (stream) await new Promise((resolve) => stream.end(resolve));
    console.log(`${root.id}: ${counts[root.id] ?? 0}件`);
  }
  const total = Object.values(counts).reduce((a, b) => a + b, 0);
  console.log(`合計 ${total}件${countOnly ? "（数えただけ）" : ` → ${outDir}`}`);
}

main().catch((error) => {
  console.error("失敗しました:", error.message ?? error);
  process.exit(1);
});
