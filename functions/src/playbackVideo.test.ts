import assert from "node:assert/strict";
import { test } from "node:test";

import {
  needsPlaybackVersion,
  parseFfmpegInfo,
  playbackStoragePath,
} from "./playbackVideo";

// 実際のデジカメ動画（P1010276.MP4）に近い`ffmpeg -i`の出力。
const kCameraOutput = `
Input #0, mov,mp4,m4a,3gp,3g2,mj2, from 'P1010276.MP4':
  Duration: 00:02:12.63, start: 0.000000, bitrate: 96339 kb/s
  Stream #0:0[0x1](eng): Video: h264 (High) (avc1 / 0x31637661), yuv420p(tv, bt709, progressive), 3840x2160 [SAR 1:1 DAR 16:9], 96064 kb/s, 29.97 fps, 29.97 tbr, 30k tbn (default)
  Stream #0:1[0x2](eng): Audio: aac (LC) (mp4a / 0x6134706D), 48000 Hz, stereo, fltp, 125 kb/s (default)
`;

test('デジカメの4K・約96Mbpsは、軽い版が要る', () => {
  const info = parseFfmpegInfo(kCameraOutput);
  assert.deepEqual(info, {
    codec: 'h264',
    width: 3840,
    height: 2160,
    bitrateKbps: 96339,
    durationSec: 132.63,
  });
  assert.equal(needsPlaybackVersion(info), true);
});

test('1080pで低ビットレートのH.264は、作らない', () => {
  const info = parseFfmpegInfo(
    `Duration: 00:00:10.00, start: 0.0, bitrate: 4000 kb/s\n` +
      `  Stream #0:0: Video: h264 (High), yuv420p, 1920x1080, 3800 kb/s, 30 fps`,
  );
  assert.equal(needsPlaybackVersion(info), false);
});

test('1080pでも高ビットレート（12Mbps超）は作る', () => {
  const info = parseFfmpegInfo(
    `Duration: 00:00:10.00, start: 0.0, bitrate: 30000 kb/s\n` +
      `  Stream #0:0: Video: h264 (High), yuv420p, 1920x1080, 29000 kb/s, 30 fps`,
  );
  assert.equal(needsPlaybackVersion(info), true);
});

test('HEVCは、小さくても作る（PCのブラウザで復号できないことが多い）', () => {
  const info = parseFfmpegInfo(
    `Duration: 00:00:10.00, start: 0.0, bitrate: 3000 kb/s\n` +
      `  Stream #0:0: Video: hevc (Main), yuv420p, 1280x720, 2800 kb/s, 30 fps`,
  );
  assert.equal(needsPlaybackVersion(info), true);
});

test('縦長のスマホ動画（1080x1920・低ビットレート）は作らない', () => {
  const info = parseFfmpegInfo(
    `Duration: 00:00:10.00, start: 0.0, bitrate: 8000 kb/s\n` +
      `  Stream #0:0: Video: h264 (High), yuv420p, 1080x1920, 7800 kb/s, 30 fps`,
  );
  assert.equal(needsPlaybackVersion(info), false);
});

test('映像の情報が取れなければ作らない', () => {
  assert.equal(parseFfmpegInfo('no streams here'), null);
  assert.equal(needsPlaybackVersion(null), false);
});

test('保存先は元のファイルの横に_play.mp4', () => {
  assert.equal(
    playbackStoragePath('dmFiles/dm1/msg1.MP4'),
    'dmFiles/dm1/msg1_play.mp4',
  );
  assert.equal(
    playbackStoragePath('groupFiles/g1/msg2/0.mov'),
    'groupFiles/g1/msg2/0_play.mp4',
  );
});
