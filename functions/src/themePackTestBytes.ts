// 意匠のテスト用に、ヘッダーだけの画像を作る（検査はヘッダーしか読まない）。HomePage の testBytes.ts と同じ。

export function pngBytes(width: number, height: number, extra = 0): Uint8Array {
    const b = new Uint8Array(33 + extra);
    b.set([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52]);
    const dv = new DataView(b.buffer);
    dv.setUint32(16, width);
    dv.setUint32(20, height);
    return b;
}

export function jpegBytes(width: number, height: number): Uint8Array {
    // SOI, APP0（長さ4）, SOF0
    const b = new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x04, 0x00, 0x00, 0xff, 0xc0, 0x00, 0x11, 0x08, 0, 0, 0, 0, 0x03, 0, 0, 0, 0, 0, 0, 0, 0, 0]);
    const dv = new DataView(b.buffer);
    dv.setUint16(13, height);
    dv.setUint16(15, width);
    return b;
}

export function webpVp8xBytes(width: number, height: number): Uint8Array {
    const b = new Uint8Array(30);
    b.set([0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x57, 0x45, 0x42, 0x50, 0x56, 0x50, 0x38, 0x58, 10, 0, 0, 0]);
    const w = width - 1;
    const h = height - 1;
    b.set([w & 0xff, (w >> 8) & 0xff, (w >> 16) & 0xff], 24);
    b.set([h & 0xff, (h >> 8) & 0xff, (h >> 16) & 0xff], 27);
    return b;
}

export function webpLosslessBytes(width: number, height: number): Uint8Array {
    const b = new Uint8Array(30);
    b.set([0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x57, 0x45, 0x42, 0x50, 0x56, 0x50, 0x38, 0x4c, 5, 0, 0, 0, 0x2f]);
    const w = width - 1;
    const h = height - 1;
    b[21] = w & 0xff;
    b[22] = ((w >> 8) & 0x3f) | ((h & 0x03) << 6);
    b[23] = (h >> 2) & 0xff;
    b[24] = (h >> 10) & 0x0f;
    return b;
}

export function webpLossyBytes(width: number, height: number): Uint8Array {
    const b = new Uint8Array(32);
    b.set([0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x57, 0x45, 0x42, 0x50, 0x56, 0x50, 0x38, 0x20, 10, 0, 0, 0, 0, 0, 0, 0x9d, 0x01, 0x2a]);
    const dv = new DataView(b.buffer);
    dv.setUint16(26, width, true);
    dv.setUint16(28, height, true);
    return b;
}


export const text = (s: string) => new TextEncoder().encode(s);

export const samplePackJson = (overrides: Record<string, unknown> = {}) =>
  JSON.stringify({
    formatVersion: 1,
    id: "test-pack",
    name: "テスト",
    author: "誰か",
    brightness: "light",
    colors: { light: { accent: "#C2185B", background: "#FFF1F5", panel: "#FDE3EB", text: "#3A1F2A", onAccent: "#FFFFFF", line: "#3A1F2A" } },
    images: { background: "background.png" },
    ...overrides,
  });
