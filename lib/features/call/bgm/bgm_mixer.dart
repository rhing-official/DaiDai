/// 通話のBGM（2026-11-03）。マイク音声と、端末内の曲を混ぜて1本の送信トラックにする。
/// `AudioContext`はWebにしか無い為、Webだけ実装し、それ以外は未対応（[BgmMixer.isSupported]が
/// false）を返す。条件付きexportで切り替える（`camera_presence`と同じ作り）。
library;

export 'bgm_mixer_stub.dart' if (dart.library.js_interop) 'bgm_mixer_web.dart';
