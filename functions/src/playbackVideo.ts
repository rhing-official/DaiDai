/**
 * 重い動画（高ビットレート・4Kなど）の再生用の軽い版を作るための、純粋な判定・解析
 * （2026-11-08）。`ref`やFirebaseに依存しない。
 *
 * 背景: デジカメの4K動画（H.264 level 5.1・約96Mbps）は、PCのブラウザではデコーダーの
 * 上限を超えて音声だけが流れ、スマホでも通信・デコードが追いつかず固まって音声まで止まる。
 * 容量ではなくビットレートと解像度が原因なので、これらが重い動画にだけ、最大1080p・
 * 約8Mbps以下のH.264を別に作って再生に使う（元のファイルはダウンロード用に残す）。
 */

export type VideoInfo = {
  codec: string;
  width: number;
  height: number;
  /** 全体のビットレート（kb/s）。分からなければnull。 */
  bitrateKbps: number | null;
  durationSec: number | null;
};

/** `ffmpeg -i <file>`が標準エラーに出す情報から、映像の情報を取り出す（ffprobeは
 * `ffmpeg-static`に含まれない為）。映像ストリームが見つからなければnull。 */
export function parseFfmpegInfo(stderr: string): VideoInfo | null {
  const video = /Stream #\d+:\d+[^\n]*?: Video: ([A-Za-z0-9_]+)[^\n]*?(\d{2,5})x(\d{2,5})/.exec(
    stderr,
  );
  if (!video) return null;
  const bitrate = /Duration:[^\n]*?bitrate: (\d+) kb\/s/.exec(stderr);
  const duration = /Duration: (\d+):(\d+):(\d+(?:\.\d+)?)/.exec(stderr);
  return {
    codec: video[1].toLowerCase(),
    width: Number(video[2]),
    height: Number(video[3]),
    bitrateKbps: bitrate ? Number(bitrate[1]) : null,
    durationSec: duration
      ? Number(duration[1]) * 3600 + Number(duration[2]) * 60 + Number(duration[3])
      : null,
  };
}

/** 1080p（1920×1080）をこの割合まで超えても、まだ1080p扱い（1088など）。 */
const kMaxPixels = 1920 * 1088;

/** これを超えるビットレート（kb/s）の動画は軽い版を作る。 */
export const kMaxPlayableBitrateKbps = 12000;

/** 軽い版を作る動画の長さの上限（秒）。関数の制限時間（イベント起動は最大540秒）に
 * 変換が収まる範囲に絞る。 */
export const kMaxPlaybackSourceSeconds = 600;

/** 変換に使ってよい時間（ミリ秒）。制限時間540秒のうち、ダウンロード・アップロード・記録の
 * 分を残して打ち切る。 */
export const kPlaybackTranscodeBudgetMs = 420_000;

/** 軽い版が要るか。H.264以外（HEVCなどはPCのブラウザで復号できないことが多い）、
 * 1080pを超える解像度、高ビットレートのどれかなら要る。情報が取れなければ作らない。 */
export function needsPlaybackVersion(info: VideoInfo | null): boolean {
  if (!info) return false;
  if (info.codec !== "h264") return true;
  if (info.width * info.height > kMaxPixels) return true;
  return info.bitrateKbps !== null && info.bitrateKbps > kMaxPlayableBitrateKbps;
}

/** 軽い版の保存先。元のファイルと同じ場所に`_play.mp4`を付ける（`_thumb.jpg`と同じ規則）。
 * 保存先のパスを真の情報として記録し、URLは併記するだけにする（移行時に書き換えない為）。 */
export function playbackStoragePath(sourcePath: string): string {
  return sourcePath.replace(/\.[^./]+$/, "") + "_play.mp4";
}

/** 短辺が1080px以下に収まるようにする`scale`フィルタ（縦長も横長も同じ規則。回転は
 * ffmpegが先に反映する）。偶数に丸める。 */
export const kPlaybackScaleFilter =
  "scale='if(gt(iw,ih),-2,min(1080,iw))':'if(gt(iw,ih),min(1080,ih),-2)'";

/** 軽い版を作るffmpegの出力オプション。 */
export const kPlaybackOutputOptions = [
  "-map",
  "0:v:0",
  "-map",
  "0:a:0?",
  "-sn",
  "-dn",
  "-c:v",
  "libx264",
  "-preset",
  "veryfast",
  "-crf",
  "24",
  "-maxrate",
  "8M",
  "-bufsize",
  "16M",
  "-pix_fmt",
  "yuv420p",
  "-profile:v",
  "high",
  "-c:a",
  "aac",
  "-b:a",
  "128k",
  "-movflags",
  "+faststart",
  "-threads",
  "0",
];
