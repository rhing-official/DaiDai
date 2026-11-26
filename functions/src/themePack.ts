// 素材パックの検査（サーバー側）。HomePage の `src/lib/themePack/` の `spec.ts`・`contrast.ts`・
// `imageSize.ts` を、規則・上限・文言とも揃えて移植したもの（2026-11-26）。形式の一次情報は
// DaiDai 本体の `lib/theme_pack/theme_pack.dart` の `ThemePackParser`。
// HomePage の検査は投稿者への案内で、信頼の根拠はここの再検査。規則を変える時は、
// HomePage・アプリ・ここの3か所と、各テストの入力例を揃えること。


/** 素材パックの形式の版。アプリが読めるのは、この版以下 */
export const THEME_PACK_FORMAT_VERSION = 1;

export const THEME_PACK_LIMITS = {
    /** 背景画像の各辺（px） */
    imageMaxSide: 2048,
    /** 画像1枚の容量（バイト） */
    imageMaxBytes: 2 * 1024 * 1024,
    /** zip全体（展開後の合計）の容量（バイト） */
    totalMaxBytes: 3 * 1024 * 1024,
    /** zipの中のファイル数（pack.jsonを含む） */
    maxFiles: 20,
    /** pack.jsonの容量（バイト） */
    packJsonMaxBytes: 64 * 1024,
    /** 1人が投稿できる件数（公開中と審査中の合計）。手順②以降で使う */
    maxPacksPerUser: 5,
} as const;

export const SHAPE_RANGES = {
    borderWidth: { min: 0, max: 6, fallback: 2.5 },
    radius: { min: 0, max: 32, fallback: 8 },
    shadowOffset: { min: -12, max: 12, fallback: [4, 4] as [number, number] },
} as const;

export type ThemePackBrightness = "light" | "dark" | "both";

export type ThemePackColorKey = "accent" | "background" | "panel" | "text" | "onAccent" | "line";
export const COLOR_KEYS: ThemePackColorKey[] = ["accent", "background", "panel", "text", "onAccent", "line"];
export const COLOR_LABELS: Record<ThemePackColorKey, string> = {
    accent: "強調色",
    background: "背景",
    panel: "パネル",
    text: "文字",
    onAccent: "強調色の上の文字",
    line: "枠線",
};

/** 色。`#RRGGBB`に正規化した文字列（透明度は捨てる）。未指定はundefined */
export type ThemePackColors = Partial<Record<ThemePackColorKey, string>>;

export type ParsedThemePack = {
    formatVersion: number;
    id: string;
    name: string;
    author: string;
    brightness: ThemePackBrightness;
    shape: { borderWidth: number; radius: number; shadowOffset: [number, number] };
    colors: { light: ThemePackColors; dark: ThemePackColors };
    backgroundImage?: string;
};

export type ParseResult =
    | { ok: true; pack: ParsedThemePack; warnings: string[] }
    | { ok: false; error: string };

const ID_PATTERN = /^[a-z0-9-]{1,40}$/;
const IMAGE_FILE_PATTERN = /^[A-Za-z0-9_-]+(\.[A-Za-z0-9]+)?$/;

function isRecord(v: unknown): v is Record<string, unknown> {
    return typeof v === "object" && v !== null && !Array.isArray(v);
}

/**
 * `RRGGBB` / `#RRGGBB` / `RRGGBBAA` / `#RRGGBBAA` を、`#RRGGBB`（大文字）に直す。8桁は、末尾2桁を透明度として捨てる。
 * 不正な形式はnull。DaiDai本体の `tryParseHexColor` と同じ。
 */
export function normalizeHexColor(input: string): { hex: string; hadAlpha: boolean } | null {
    const body = input.trim().replace(/^#/, "");
    if (!/^[0-9a-fA-F]{6}$|^[0-9a-fA-F]{8}$/.test(body)) return null;
    return { hex: `#${body.slice(0, 6).toUpperCase()}`, hadAlpha: body.length === 8 };
}

function clamp(value: number, min: number, max: number): number {
    if (Number.isNaN(value)) return min;
    return Math.min(max, Math.max(min, value));
}

/** 範囲外なら、投稿者への警告を足して、丸めた値を返す（アプリ側の丸めと同じ結果） */
function readNumber(
    value: unknown,
    range: { min: number; max: number; fallback: number },
    label: string,
    warnings: string[],
): number {
    if (typeof value !== "number" || !Number.isFinite(value)) {
        if (value !== undefined) warnings.push(`${label}は数値で書いてください。標準の値になります。`);
        return range.fallback;
    }
    const clamped = clamp(value, range.min, range.max);
    if (clamped !== value) {
        warnings.push(`${label}が範囲外です。${range.min}〜${range.max}で書いてください。アプリでは${clamped}になります。`);
    }
    return clamped;
}

function readColors(value: unknown, scope: "light" | "dark", warnings: string[]): ThemePackColors {
    const out: ThemePackColors = {};
    if (!isRecord(value)) return out;
    for (const key of COLOR_KEYS) {
        const raw = value[key];
        if (raw === undefined) continue;
        const where = `${scope === "light" ? "明るい" : "暗い"}外観の${COLOR_LABELS[key]}`;
        if (typeof raw !== "string") {
            warnings.push(`${where}の色は、文字列で書いてください。未指定として扱われます。`);
            continue;
        }
        const parsed = normalizeHexColor(raw);
        if (!parsed) {
            warnings.push(`${where}の色が正しい形式ではありません。#RRGGBBで書いてください。未指定として扱われます。`);
            continue;
        }
        if (parsed.hadAlpha) warnings.push(`${where}の色は、透明度を含んでいます。透明度は使われず、不透明になります。`);
        out[key] = parsed.hex;
    }
    return out;
}

/**
 * pack.jsonの文字列を読む。致命的な誤りは `{ok:false}`、範囲外の数値や不正な色は、警告つきで `{ok:true}`。
 * 検査の順序と、エラーにする条件は、DaiDai本体の `ThemePackParser.parse` と同じ。
 */
export function parseThemePack(source: string): ParseResult {
    let json: unknown;
    try {
        json = JSON.parse(source);
    } catch {
        return { ok: false, error: "pack.jsonが壊れています。JSONとして読めません。" };
    }
    if (!isRecord(json)) return { ok: false, error: "pack.jsonの形が正しくありません。最上位は、波括弧で囲んだ項目の集まりにしてください。" };

    const formatVersion = json.formatVersion;
    if (typeof formatVersion !== "number" || !Number.isInteger(formatVersion)) {
        return { ok: false, error: "formatVersionが書かれていません。整数で書いてください。" };
    }
    if (formatVersion > THEME_PACK_FORMAT_VERSION) {
        return { ok: false, error: `formatVersionが${formatVersion}です。このアプリが読めるのは、${THEME_PACK_FORMAT_VERSION}以下です。` };
    }

    const id = json.id;
    if (typeof id !== "string" || !ID_PATTERN.test(id)) {
        return { ok: false, error: "idが正しくありません。半角の小文字・数字・ハイフンで、1〜40文字にしてください。" };
    }

    const name = json.name;
    if (typeof name !== "string" || name.trim().length === 0 || name.length > 40) {
        return { ok: false, error: "nameが正しくありません。1〜40文字にしてください。" };
    }

    const warnings: string[] = [];
    const author = typeof json.author === "string" ? json.author : "";
    if (typeof json.author !== "string") warnings.push("authorが文字列で書かれていません。投稿者名は、DaiDaiの呼び名が表示されます。");

    const b = json.brightness;
    const brightness: ThemePackBrightness = b === "light" || b === "dark" || b === "both" ? b : "both";
    if (b !== undefined && brightness !== b) warnings.push("brightnessは、light・dark・bothのどれかで書いてください。bothとして扱われます。");

    const shapeSrc = isRecord(json.shape) ? json.shape : {};
    const borderWidth = readNumber(shapeSrc.borderWidth, SHAPE_RANGES.borderWidth, "shapeのborderWidth", warnings);
    const radius = readNumber(shapeSrc.radius, SHAPE_RANGES.radius, "shapeのradius", warnings);
    let shadowOffset: [number, number] = [...SHAPE_RANGES.shadowOffset.fallback];
    const so = shapeSrc.shadowOffset;
    if (so !== undefined) {
        if (Array.isArray(so) && so.length === 2 && so.every((n) => typeof n === "number" && Number.isFinite(n))) {
            const range = { min: SHAPE_RANGES.shadowOffset.min, max: SHAPE_RANGES.shadowOffset.max };
            const x = clamp(so[0] as number, range.min, range.max);
            const y = clamp(so[1] as number, range.min, range.max);
            if (x !== so[0] || y !== so[1]) {
                warnings.push(`shapeのshadowOffsetが範囲外です。各${range.min}〜${range.max}で書いてください。アプリでは[${x}, ${y}]になります。`);
            }
            shadowOffset = [x, y];
        } else {
            warnings.push("shapeのshadowOffsetは、数値2つの並びで書いてください。標準の値になります。");
        }
    }

    const colorsSrc = isRecord(json.colors) ? json.colors : {};
    const colors = {
        light: readColors(colorsSrc.light, "light", warnings),
        dark: readColors(colorsSrc.dark, "dark", warnings),
    };

    let backgroundImage: string | undefined;
    const imagesSrc = isRecord(json.images) ? json.images : {};
    const bg = imagesSrc.background;
    if (bg !== undefined) {
        if (typeof bg !== "string" || !IMAGE_FILE_PATTERN.test(bg)) {
            return {
                ok: false,
                error: "背景画像のファイル名が正しくありません。ディレクトリや「..」、URLは使えません。英数字・アンダースコア・ハイフンと、拡張子だけにしてください。",
            };
        }
        backgroundImage = bg;
    }

    return {
        ok: true,
        pack: { formatVersion, id, name: name.trim(), author, brightness, shape: { borderWidth, radius, shadowOffset }, colors, backgroundImage },
        warnings,
    };
}

// ---------------- コントラスト（HomePage の contrast.ts） ----------------


// WCAG 2.x のコントラスト比。全ての組で、3:1以上にする（大きな文字・画面の部品の基準。AAの本文の基準は4.5:1）。
// 当初は4.5:1だったが、同梱の公式パック（桜 4.21、水玉 3.76）が届かないため、全ての組を3:1に緩めた（2026-11-26、ユーザー判断）。

export const MIN_CONTRAST_RATIO = 3;

function channel(v: number): number {
    const s = v / 255;
    return s <= 0.03928 ? s / 12.92 : Math.pow((s + 0.055) / 1.055, 2.4);
}

/** `#RRGGBB` の相対輝度（0〜1） */
export function relativeLuminance(hex: string): number {
    const n = parseInt(hex.replace(/^#/, "").slice(0, 6), 16);
    const r = (n >> 16) & 0xff;
    const g = (n >> 8) & 0xff;
    const b = n & 0xff;
    return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b);
}

/** 2色のコントラスト比（1〜21） */
export function contrastRatio(a: string, b: string): number {
    const la = relativeLuminance(a);
    const lb = relativeLuminance(b);
    const [hi, lo] = la >= lb ? [la, lb] : [lb, la];
    return (hi + 0.05) / (lo + 0.05);
}

/** 検査する色の組。文字（前景）と、その下の色（背景） */
export const CONTRAST_PAIRS: { fg: ThemePackColorKey; bg: ThemePackColorKey }[] = [
    { fg: "text", bg: "background" },
    { fg: "text", bg: "panel" },
    { fg: "onAccent", bg: "accent" },
];

export type ContrastCheck = {
    scope: "light" | "dark";
    fg: ThemePackColorKey;
    bg: ThemePackColorKey;
    fgHex: string;
    bgHex: string;
    ratio: number;
    pass: boolean;
};

export type ContrastReport = {
    checks: ContrastCheck[];
    /** 片方の色が未指定で、検査できなかった組。アプリが版画の標準で導くため、横丁では確認できない */
    skipped: { scope: "light" | "dark"; fg: ThemePackColorKey; bg: ThemePackColorKey }[];
};

function scopesFor(brightness: ParsedThemePack["brightness"]): ("light" | "dark")[] {
    return brightness === "both" ? ["light", "dark"] : [brightness];
}

/** 明るさ別に（bothは両方）、両方の色が指定されている組だけを検査する */
export function checkContrast(pack: ParsedThemePack): ContrastReport {
    const checks: ContrastCheck[] = [];
    const skipped: ContrastReport["skipped"] = [];
    for (const scope of scopesFor(pack.brightness)) {
        const colors: ThemePackColors = pack.colors[scope];
        for (const { fg, bg } of CONTRAST_PAIRS) {
            const fgHex = colors[fg];
            const bgHex = colors[bg];
            if (!fgHex || !bgHex) {
                // 組のどちらも未指定なら、何も使っていないので、報告しない
                if (fgHex || bgHex) skipped.push({ scope, fg, bg });
                continue;
            }
            const ratio = contrastRatio(fgHex, bgHex);
            checks.push({ scope, fg, bg, fgHex, bgHex, ratio, pass: ratio >= MIN_CONTRAST_RATIO });
        }
    }
    return { checks, skipped };
}

/** 検査の結果を、投稿者向けの1行にする */
export function describeContrast(c: Pick<ContrastCheck, "scope" | "fg" | "bg" | "ratio">): string {
    const scope = c.scope === "light" ? "明るい外観" : "暗い外観";
    return `${scope}の「${COLOR_LABELS[c.fg]}」と「${COLOR_LABELS[c.bg]}」のコントラスト比は ${c.ratio.toFixed(2)} です`;
}

// ---------------- 画像のヘッダー（HomePage の imageSize.ts） ----------------

export type ImageType = "png" | "webp" | "jpeg";
export type ImageInfo = { type: ImageType; width: number; height: number };

const u16be = (b: Uint8Array, o: number) => (b[o] << 8) | b[o + 1];
const u32be = (b: Uint8Array, o: number) => ((b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3]) >>> 0;
const u16le = (b: Uint8Array, o: number) => b[o] | (b[o + 1] << 8);
const u24le = (b: Uint8Array, o: number) => b[o] | (b[o + 1] << 8) | (b[o + 2] << 16);
const ascii = (b: Uint8Array, o: number, n: number) => String.fromCharCode(...b.subarray(o, o + n));

function readPng(b: Uint8Array): ImageInfo | null {
    const sig = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
    if (b.length < 24 || !sig.every((v, i) => b[i] === v)) return null;
    if (ascii(b, 12, 4) !== "IHDR") return null;
    return { type: "png", width: u32be(b, 16), height: u32be(b, 20) };
}

function readJpeg(b: Uint8Array): ImageInfo | null {
    if (b.length < 4 || b[0] !== 0xff || b[1] !== 0xd8) return null;
    let o = 2;
    while (o + 4 <= b.length) {
        if (b[o] !== 0xff) return null;
        // 区切りの0xFFが続くことがある
        while (b[o] === 0xff && o < b.length) o++;
        const marker = b[o];
        o++;
        // 長さを持たないマーカー
        if (marker === 0xd8 || marker === 0x01 || (marker >= 0xd0 && marker <= 0xd7)) continue;
        if (marker === 0xd9 || marker === 0xda) return null;
        if (o + 2 > b.length) return null;
        const len = u16be(b, o);
        const isSof = marker >= 0xc0 && marker <= 0xcf && marker !== 0xc4 && marker !== 0xc8 && marker !== 0xcc;
        if (isSof) {
            if (o + 7 > b.length) return null;
            return { type: "jpeg", height: u16be(b, o + 3), width: u16be(b, o + 5) };
        }
        o += len;
    }
    return null;
}

function readWebp(b: Uint8Array): ImageInfo | null {
    if (b.length < 30 || ascii(b, 0, 4) !== "RIFF" || ascii(b, 8, 4) !== "WEBP") return null;
    const kind = ascii(b, 12, 4);
    const d = 20; // チャンクの中身の始まり
    if (kind === "VP8 ") {
        // 非可逆。フレームの開始コード 9D 01 2A の後ろに、幅と高さ（各14ビット）
        if (b[d + 3] !== 0x9d || b[d + 4] !== 0x01 || b[d + 5] !== 0x2a) return null;
        return { type: "webp", width: u16le(b, d + 6) & 0x3fff, height: u16le(b, d + 8) & 0x3fff };
    }
    if (kind === "VP8L") {
        // 可逆。署名0x2Fの後ろに、幅-1と高さ-1（各14ビット）
        if (b[d] !== 0x2f) return null;
        const b1 = b[d + 1], b2 = b[d + 2], b3 = b[d + 3], b4 = b[d + 4];
        const width = 1 + (((b2 & 0x3f) << 8) | b1);
        const height = 1 + (((b4 & 0x0f) << 10) | (b3 << 2) | ((b2 & 0xc0) >> 6));
        return { type: "webp", width, height };
    }
    if (kind === "VP8X") {
        // 拡張。幅-1と高さ-1（各24ビット）
        return { type: "webp", width: 1 + u24le(b, d + 4), height: 1 + u24le(b, d + 7) };
    }
    return null;
}

/** png / webp / jpeg のいずれかなら、形式と大きさ。それ以外、または壊れていればnull */
export function readImageInfo(bytes: Uint8Array): ImageInfo | null {
    return readPng(bytes) ?? readJpeg(bytes) ?? readWebp(bytes);
}

/** 拡張子（小文字）から期待する形式。対応しない拡張子はnull */
export function imageTypeForExtension(ext: string): ImageType | null {
    switch (ext.toLowerCase()) {
        case "png":
            return "png";
        case "webp":
            return "webp";
        case "jpg":
        case "jpeg":
            return "jpeg";
        default:
            return null;
    }
}

// ---------------- 提出されたファイルの検査（HomePage の validate.ts の、zip を除く部分） ----------------

export function formatBytes(n: number): string {
    if (n >= 1024 * 1024) return `${(n / (1024 * 1024)).toFixed(n % (1024 * 1024) === 0 ? 0 : 1)}MB`;
    if (n >= 1024) return `${Math.round(n / 1024)}KB`;
    return `${n}バイト`;
}

const PACK_FILE = "pack.json";

/** 実行できる形式・スクリプトとして扱われる拡張子。理由を分かりやすく伝えるために分ける */
const EXECUTABLE_EXTENSIONS = new Set([
    "exe", "bat", "cmd", "com", "msi", "scr", "lnk", "ps1", "vbs", "sh", "bash", "zsh",
    "js", "mjs", "cjs", "ts", "py", "rb", "pl", "php", "jar", "dll", "so", "dylib", "app", "apk", "html", "htm", "svg",
]);

function extensionOf(name: string): string {
    const i = name.lastIndexOf(".");
    return i < 0 ? "" : name.slice(i + 1).toLowerCase();
}

export type FilesValidation =
    | { ok: true; pack: ParsedThemePack; warnings: string[] }
    | { ok: false; errors: string[] };

/**
 * 保存先から読み直した提出物を検査する。`files` のキーはファイル名（フォルダを含まない）。
 * 許すのは、`pack.json` と、`images.background` が指す画像1枚だけ。errors が1つでも有れば、提出できない。
 * 警告（範囲外の数値の丸めなど）は、アプリが同じ丸めを行うため、提出は止めない。
 */
export function validateThemePackFiles(files: Map<string, Uint8Array>): FilesValidation {
    const L = THEME_PACK_LIMITS;
    const errors: string[] = [];

    if (files.size > L.maxFiles) errors.push(`ファイルが多すぎます。${L.maxFiles}個以下にしてください。`);
    let total = 0;
    for (const bytes of files.values()) total += bytes.length;
    if (total > L.totalMaxBytes) errors.push(`容量が大きすぎます。合計${formatBytes(L.totalMaxBytes)}以下にしてください。`);

    const packBytes = files.get(PACK_FILE);
    if (!packBytes) return { ok: false, errors: [...errors, "pack.jsonがありません。"] };
    if (packBytes.length > L.packJsonMaxBytes) {
        return { ok: false, errors: [...errors, `pack.jsonが大きすぎます。${formatBytes(L.packJsonMaxBytes)}以下にしてください。`] };
    }
    let source: string;
    try {
        source = new TextDecoder("utf-8", { fatal: true }).decode(packBytes);
    } catch {
        return { ok: false, errors: [...errors, "pack.jsonが、UTF-8の文字列として読めません。"] };
    }
    const parsed = parseThemePack(source);
    if (!parsed.ok) return { ok: false, errors: [...errors, parsed.error] };
    const { pack, warnings } = parsed;

    // 他のファイル。背景画像として指定された1枚だけを許す
    const bg = pack.backgroundImage;
    for (const [name, bytes] of files) {
        if (name === PACK_FILE) continue;
        if (name.startsWith(".")) {
            errors.push(`「${name}」は隠しファイルです。使えません。`);
            continue;
        }
        const ext = extensionOf(name);
        if (EXECUTABLE_EXTENSIONS.has(ext)) {
            errors.push(`「${name}」は、実行できる形式かスクリプトです。意匠パックには、コードを含められません。`);
            continue;
        }
        const expected = imageTypeForExtension(ext);
        if (!expected) {
            errors.push(`「${name}」は、使えないファイルです。pack.jsonと、png・webp・jpegの画像だけにしてください。`);
            continue;
        }
        if (name !== bg) {
            errors.push(`「${name}」は、pack.jsonの背景画像として指定されていません。背景画像は1枚だけです。`);
            continue;
        }
        if (bytes.length > L.imageMaxBytes) {
            errors.push(`「${name}」の容量が大きすぎます。1枚あたり${formatBytes(L.imageMaxBytes)}以下にしてください。`);
        }
        const info = readImageInfo(bytes);
        if (!info) {
            errors.push(`「${name}」は、画像として読めません。壊れているか、拡張子と中身の形式が違います。`);
            continue;
        }
        if (info.type !== expected) errors.push(`「${name}」の拡張子と、画像の中身の形式が一致しません。`);
        if (info.width > L.imageMaxSide || info.height > L.imageMaxSide) {
            errors.push(`「${name}」の大きさが${info.width}×${info.height}です。各辺${L.imageMaxSide}px以下にしてください。`);
        }
    }
    if (bg && !files.has(bg)) errors.push(`背景画像「${bg}」が、ありません。`);

    // コントラスト
    for (const c of checkContrast(pack).checks) {
        if (c.pass) continue;
        errors.push(`${describeContrast(c)}。読みやすさの基準は${MIN_CONTRAST_RATIO}以上です。文字の色と背景の色を、離してください。`);
    }

    return errors.length > 0 ? { ok: false, errors } : { ok: true, pack, warnings };
}
