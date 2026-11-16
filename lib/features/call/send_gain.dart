/// 相手へ送る音の音量（ゲイン、2026-11-16、Webのみ）。マイク・共有する音声のトラックを
/// `AudioContext`の`GainNode`に通した、処理後のトラックを作る。`AudioContext`はWebにしか無い為、
/// Webだけ実装し、それ以外は何もしない（[SendGain.isSupported]がfalse）。条件付きexportで切り替える
/// （`mic_denoiser`と同じ作り）。
library;

export 'send_gain_stub.dart' if (dart.library.js_interop) 'send_gain_web.dart';
