/// 通話のマイクのノイズ除去（RNNoise、2026-11-15、Webのみ）。マイクの生のトラックを
/// `AudioWorklet`（RNNoiseのWASM）に通し、処理後のトラックで置き換える。`AudioContext`は
/// Webにしか無い為、Webだけ実装し、それ以外は何もしない（[MicDenoiser.isSupported]がfalse）。
/// 条件付きexportで切り替える（`bgm_mixer`と同じ作り）。
library;

export 'mic_denoiser_stub.dart'
    if (dart.library.js_interop) 'mic_denoiser_web.dart';
