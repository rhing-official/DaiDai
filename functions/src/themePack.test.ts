// HomePage の `src/lib/themePack/` のテスト（spec・contrast・imageSize・validate）を移植したもの。
// 入力例は、DaiDai 本体の test/theme_pack_test.dart に合わせている（規則の食い違いを防ぐ）。
import assert from "node:assert/strict";
import { test } from "node:test";

import {
  checkContrast,
  contrastRatio,
  imageTypeForExtension,
  normalizeHexColor,
  parseThemePack,
  readImageInfo,
  relativeLuminance,
  THEME_PACK_LIMITS,
  validateThemePackFiles,
  type ParsedThemePack,
} from "./themePack";
import {
  jpegBytes,
  pngBytes,
  samplePackJson,
  text,
  webpLosslessBytes,
  webpLossyBytes,
  webpVp8xBytes,
} from "./themePackTestBytes";

const json = (overrides: Record<string, unknown> = {}) =>
  JSON.stringify({ formatVersion: 1, id: "test-pack", name: "テスト", author: "誰か", brightness: "both", ...overrides });

function ok(source: string) {
  const r = parseThemePack(source);
  if (!r.ok) throw new Error(r.error);
  return r;
}

// ---- spec ----

test("読み取り: 正常な意匠を読める", () => {
  const { pack, warnings } = ok(
    json({
      shape: { borderWidth: 3, radius: 12, shadowOffset: [5, 6] },
      colors: { light: { accent: "#112233", line: "#445566" }, dark: { background: "#000000" } },
      images: { background: "bg.webp" },
    }),
  );
  assert.deepEqual(pack.shape, { borderWidth: 3, radius: 12, shadowOffset: [5, 6] });
  assert.equal(pack.colors.light.accent, "#112233");
  assert.equal(pack.colors.light.line, "#445566");
  assert.equal(pack.colors.dark.background, "#000000");
  assert.equal(pack.backgroundImage, "bg.webp");
  assert.deepEqual(warnings, []);
});

test("読み取り: 範囲外の数値は、アプリと同じ値に丸め、警告を返す", () => {
  const { pack, warnings } = ok(json({ shape: { borderWidth: 99, radius: -5, shadowOffset: [100, -100] } }));
  assert.deepEqual(pack.shape, { borderWidth: 6, radius: 0, shadowOffset: [12, -12] });
  assert.equal(warnings.length, 3);
});

test("読み取り: 8桁の色は、透明度を捨てて不透明にし、警告を返す", () => {
  const { pack, warnings } = ok(json({ colors: { light: { accent: "#11223300" } } }));
  assert.equal(pack.colors.light.accent, "#112233");
  assert.ok(warnings.some((w) => w.includes("透明度")));
});

test("読み取り: 不正な色は、未指定として扱い、警告を返す", () => {
  const { pack, warnings } = ok(json({ colors: { light: { accent: "あか" } } }));
  assert.equal(pack.colors.light.accent, undefined);
  assert.equal(warnings.length, 1);
});

test("読み取り: 省略した項目は、既定値になる", () => {
  const { pack, warnings } = ok(json({}));
  assert.deepEqual(pack.shape, { borderWidth: 2.5, radius: 8, shadowOffset: [4, 4] });
  assert.equal(pack.colors.light.accent, undefined);
  assert.equal(pack.backgroundImage, undefined);
  assert.deepEqual(warnings, []);
});

test("読み取り: brightness は、不明な値なら both になる", () => {
  assert.equal(ok(json({ brightness: "dark" })).pack.brightness, "dark");
  assert.equal(ok(json({ brightness: "ふしぎ" })).pack.brightness, "both");
});

test("読み取り: 名前は、前後の空白を除いて保存する", () => {
  assert.equal(ok(json({ name: "  桜  " })).pack.name, "桜");
});

test("読み取り: 読めないもの", () => {
  const bad = [
    "{",
    "[]",
    json({ formatVersion: 99 }),
    json({ formatVersion: null }),
    json({ id: "../x" }),
    json({ id: "Sakura" }),
    json({ id: "a".repeat(41) }),
    json({ name: " " }),
    json({ name: "あ".repeat(41) }),
  ];
  for (const s of bad) assert.equal(parseThemePack(s).ok, false, s);
});

test("読み取り: 背景画像として使えないファイル名", () => {
  for (const name of ["../a.png", "/etc/passwd", "https://x/y.png", "a/b.png", "a b.png", "a.png.exe/x"]) {
    assert.equal(parseThemePack(json({ images: { background: name } })).ok, false, name);
  }
});

test("読み取り: id は、1文字と40文字までなら使える", () => {
  assert.equal(parseThemePack(json({ id: "a" })).ok, true);
  assert.equal(parseThemePack(json({ id: "a".repeat(40) })).ok, true);
});

test("色: # の有無・大文字小文字・前後の空白を受け付け、桁数や文字が違えば null", () => {
  assert.deepEqual(normalizeHexColor("d6457a"), { hex: "#D6457A", hadAlpha: false });
  assert.deepEqual(normalizeHexColor("  #D6457A "), { hex: "#D6457A", hadAlpha: false });
  assert.deepEqual(normalizeHexColor("#d6457aff"), { hex: "#D6457A", hadAlpha: true });
  assert.equal(normalizeHexColor("#FFF"), null);
  assert.equal(normalizeHexColor("#GGGGGG"), null);
  assert.equal(normalizeHexColor(""), null);
});

// ---- contrast ----

const pack = (overrides: Partial<ParsedThemePack> = {}): ParsedThemePack => ({
  formatVersion: 1,
  id: "t",
  name: "t",
  author: "",
  brightness: "light",
  shape: { borderWidth: 2.5, radius: 8, shadowOffset: [4, 4] },
  colors: { light: {}, dark: {} },
  ...overrides,
});

test("コントラスト比: 黒と白は21、同じ色は1、順序に関わらず同じ、相対輝度の端", () => {
  assert.ok(Math.abs(contrastRatio("#000000", "#FFFFFF") - 21) < 1e-5);
  assert.ok(Math.abs(contrastRatio("#336699", "#336699") - 1) < 1e-5);
  assert.ok(Math.abs(contrastRatio("#FFFFFF", "#777777") - contrastRatio("#777777", "#FFFFFF")) < 1e-10);
  assert.equal(relativeLuminance("#000000"), 0);
  assert.ok(Math.abs(relativeLuminance("#FFFFFF") - 1) < 1e-5);
});

test("コントラスト: 薄い背景に白い文字は、不合格", () => {
  const r = checkContrast(pack({ colors: { light: { text: "#FFFFFF", background: "#FFF1F5" }, dark: {} } }));
  assert.equal(r.checks.length, 1);
  assert.equal(r.checks[0].pass, false);
});

test("コントラスト: 読みやすい配色は、全ての組で合格", () => {
  const r = checkContrast(
    pack({
      colors: {
        light: { accent: "#C2185B", background: "#FFF1F5", panel: "#FDE3EB", text: "#3A1F2A", onAccent: "#FFFFFF", line: "#3A1F2A" },
        dark: {},
      },
    }),
  );
  assert.equal(r.checks.length, 3);
  assert.ok(r.checks.every((c) => c.pass));
});

test("コントラスト: 同梱の公式意匠「桜」は、強調色と文字が4.21で、基準（3）を満たす", () => {
  const r = checkContrast(
    pack({
      colors: {
        light: { accent: "#D6457A", background: "#FFF1F5", panel: "#FDE3EB", text: "#3A1F2A", onAccent: "#FFFFFF", line: "#3A1F2A" },
        dark: {},
      },
    }),
  );
  const ratio = r.checks.find((c) => c.fg === "onAccent")!.ratio;
  assert.ok(Math.abs(ratio - 4.21) < 0.005);
  assert.ok(r.checks.every((c) => c.pass));
});

test("コントラスト: 基準（3）の境目。#949494と白は合格、#959595は不合格", () => {
  assert.ok(contrastRatio("#949494", "#FFFFFF") >= 3);
  assert.ok(contrastRatio("#959595", "#FFFFFF") < 3);
  assert.equal(checkContrast(pack({ colors: { light: { text: "#949494", background: "#FFFFFF" }, dark: {} } })).checks[0].pass, true);
  assert.equal(checkContrast(pack({ colors: { light: { text: "#959595", background: "#FFFFFF" }, dark: {} } })).checks[0].pass, false);
});

test("コントラスト: both なら両方の外観、light だけなら暗い外観は検査しない", () => {
  const both = checkContrast(
    pack({ brightness: "both", colors: { light: { text: "#000000", background: "#FFFFFF" }, dark: { text: "#000000", background: "#111111" } } }),
  );
  assert.deepEqual(both.checks.map((c) => [c.scope, c.pass]), [["light", true], ["dark", false]]);
  const light = checkContrast(pack({ brightness: "light", colors: { light: {}, dark: { text: "#000000", background: "#000000" } } }));
  assert.equal(light.checks.length, 0);
});

test("コントラスト: 片方の色だけの組は skipped、何も無い組は報告しない", () => {
  const r = checkContrast(pack({ colors: { light: { text: "#000000" }, dark: {} } }));
  assert.equal(r.checks.length, 0);
  assert.deepEqual(r.skipped, [
    { scope: "light", fg: "text", bg: "background" },
    { scope: "light", fg: "text", bg: "panel" },
  ]);
  const none = checkContrast(pack());
  assert.equal(none.checks.length + none.skipped.length, 0);
});

// ---- imageSize ----

test("画像のヘッダー: png・jpeg・webp の3種の形式と大きさ", () => {
  assert.deepEqual(readImageInfo(pngBytes(1080, 1920)), { type: "png", width: 1080, height: 1920 });
  assert.deepEqual(readImageInfo(jpegBytes(640, 480)), { type: "jpeg", width: 640, height: 480 });
  assert.deepEqual(readImageInfo(webpVp8xBytes(2048, 1024)), { type: "webp", width: 2048, height: 1024 });
  assert.deepEqual(readImageInfo(webpLosslessBytes(800, 600)), { type: "webp", width: 800, height: 600 });
  assert.deepEqual(readImageInfo(webpLossyBytes(320, 200)), { type: "webp", width: 320, height: 200 });
});

test("画像のヘッダー: 画像でないものや壊れたものは null", () => {
  assert.equal(readImageInfo(text("hello world, this is not an image at all")), null);
  assert.equal(readImageInfo(new Uint8Array(0)), null);
  assert.equal(readImageInfo(pngBytes(10, 10).subarray(0, 12)), null);
});

test("画像: 拡張子から期待する形式", () => {
  assert.equal(imageTypeForExtension("PNG"), "png");
  assert.equal(imageTypeForExtension("jpg"), "jpeg");
  assert.equal(imageTypeForExtension("jpeg"), "jpeg");
  assert.equal(imageTypeForExtension("webp"), "webp");
  assert.equal(imageTypeForExtension("gif"), null);
  assert.equal(imageTypeForExtension("svg"), null);
});

// ---- 提出されたファイルの検査（HomePage の validate.test.ts に相当） ----

const goodFiles = () => new Map<string, Uint8Array>([["pack.json", text(samplePackJson())], ["background.png", pngBytes(1080, 1920)]]);
const errorsOf = (files: Map<string, Uint8Array>) => {
  const r = validateThemePackFiles(files);
  return r.ok ? [] : r.errors;
};

test("ファイルの検査: 正常な意匠は合格し、背景画像なしでも合格する", () => {
  const r = validateThemePackFiles(goodFiles());
  assert.equal(r.ok, true);
  if (r.ok) assert.equal(r.pack.id, "test-pack");
  const noImage = new Map([["pack.json", text(samplePackJson({ images: undefined }))]]);
  assert.equal(validateThemePackFiles(noImage).ok, true);
});

test("ファイルの検査: pack.json が無い・壊れている・UTF-8でない・大きすぎる", () => {
  assert.match(errorsOf(new Map([["background.png", pngBytes(10, 10)]])).join(), /pack\.json/);
  assert.equal(validateThemePackFiles(new Map([["pack.json", text("{")]])).ok, false);
  assert.match(errorsOf(new Map([["pack.json", new Uint8Array([0xff, 0xfe, 0xfd])]])).join(), /UTF-8/);
  const big = new Uint8Array(THEME_PACK_LIMITS.packJsonMaxBytes + 1).fill(0x20);
  assert.match(errorsOf(new Map([["pack.json", big]])).join(), /大きすぎ/);
});

test("ファイルの検査: 隠しファイル・実行形式・使えない形式・背景に指定されていない画像は不合格", () => {
  for (const name of [".secret", "run.sh", "setup.exe", "a.js", "x.py", "index.html", "icon.svg", "a.gif", "extra.png"]) {
    const files = goodFiles();
    files.set(name, name === "extra.png" ? pngBytes(10, 10) : text("x"));
    assert.equal(validateThemePackFiles(files).ok, false, name);
  }
});

test("ファイルの検査: 背景画像の指定が有るのに、ファイルが無ければ不合格", () => {
  const files = new Map([["pack.json", text(samplePackJson())]]);
  assert.match(errorsOf(files).join(), /ありません/);
});

test("ファイルの検査: 画像の偽装（拡張子と中身の不一致・画像でない中身）は不合格", () => {
  const jpegAsPng = goodFiles();
  jpegAsPng.set("background.png", jpegBytes(100, 100));
  assert.match(errorsOf(jpegAsPng).join(), /一致しません/);
  const notImage = goodFiles();
  notImage.set("background.png", text("MZ これは実行ファイルです。画像ではありません。"));
  assert.match(errorsOf(notImage).join(), /画像として読めません/);
});

test("ファイルの検査: 大きさの上限（2048px）は、ちょうどなら合格、超えれば不合格", () => {
  const exact = goodFiles();
  exact.set("background.png", pngBytes(2048, 2048));
  assert.equal(validateThemePackFiles(exact).ok, true);
  const over = goodFiles();
  over.set("background.png", pngBytes(2049, 100));
  assert.match(errorsOf(over).join(), /2048px/);
  const huge = goodFiles();
  huge.set("background.png", pngBytes(65535, 65535));
  assert.equal(validateThemePackFiles(huge).ok, false);
});

test("ファイルの検査: 画像1枚の容量（2MB）と合計（3MB）の上限", () => {
  const big = goodFiles();
  big.set("background.png", pngBytes(10, 10, THEME_PACK_LIMITS.imageMaxBytes));
  assert.match(errorsOf(big).join(), /容量が大きすぎ/);
  const total = goodFiles();
  total.set("background.png", pngBytes(10, 10, THEME_PACK_LIMITS.imageMaxBytes - 33));
  total.set("pack.json", text(samplePackJson({ padding: "x".repeat(60 * 1024) })));
  total.set("b.png", pngBytes(10, 10, THEME_PACK_LIMITS.imageMaxBytes - 33));
  assert.equal(validateThemePackFiles(total).ok, false);
});

test("ファイルの検査: ファイル数が多すぎれば不合格", () => {
  const files = goodFiles();
  for (let i = 0; i < THEME_PACK_LIMITS.maxFiles; i++) files.set(`f${i}.png`, pngBytes(1, 1));
  assert.equal(validateThemePackFiles(files).ok, false);
});

test("ファイルの検査: コントラスト不足（3:1未満）と不正な色", () => {
  const low = goodFiles();
  low.set("pack.json", text(samplePackJson({ colors: { light: { text: "#FFFFFF", background: "#FFF1F5" } } })));
  assert.match(errorsOf(low).join(), /コントラスト比/);
  // 不正な色は、未指定として扱われ、警告だけで通る（アプリの挙動と同じ）
  const badColor = goodFiles();
  badColor.set("pack.json", text(samplePackJson({ colors: { light: { accent: "あか" } } })));
  const r = validateThemePackFiles(badColor);
  assert.equal(r.ok, true);
  if (r.ok) assert.equal(r.warnings.length, 1);
});
