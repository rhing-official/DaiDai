import 'package:flutter/foundation.dart';

import '../../utils/screen_orientation/screen_orientation.dart';

/// getUserMedia用の音声制約。
///
/// Android実機では、入れ子になった詳細な音声制約マップ（echoCancellation等の
/// キー付きMap）が正しく解釈されず、マイクが機能しなくなる既知の不具合報告が
/// ある（flutter-webrtc issue #1972, #1433, dart-sip-ua#401）。そのため
/// Androidでは単純化した`true`指定にフォールバックし、ネイティブ側の
/// デフォルトのAEC/NS/AGCに委ねる。Web/iOS/デスクトップでは詳細な制約マップを
/// そのまま使う。
///
/// 注記: ここで指定できるのはあくまでWebRTC標準のエコー除去・ノイズ抑制・
/// 自動ゲイン調整であり、Krisp等が行うような機械学習ベースのノイズ除去とは
/// 原理的に別物で、性能差は埋まらない。本格対応はフェーズ3のRNNoise統合を待つ
/// （CLAUDE.md参照）。
dynamic buildAudioConstraints() {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    return true;
  }
  return {
    'echoCancellation': true,
    'noiseSuppression': true,
    'autoGainControl': true,
    // レガシー（Chromium/libwebrtcネイティブ層）向けの補助キー。対応していない
    // 環境では単に無視されるため害はないが、効果があるとは保証されない。
    'googEchoCancellation': true,
    'googNoiseSuppression': true,
    'googAutoGainControl': true,
    'googHighpassFilter': true,
  };
}

/// カメラの映像制約。ブラウザで画面が縦向きの時は、解像度の縦横を入れ替える
/// （横長固定で要求すると、縦向きのiPad等で映像が送られなくなる不具合の対処、
/// 2026-10-22）。[frontCamera]がfalseなら背面カメラ。
Map<String, dynamic> buildVideoConstraints({bool frontCamera = true}) =>
    videoConstraintsFor(
      portrait: kIsWeb && isPortraitScreen,
      frontCamera: frontCamera,
      withAspectRatio: kIsWeb,
    );

/// [buildVideoConstraints]の中身（向きを引数にした純粋な関数、テスト用）。
/// [withAspectRatio]がtrueなら、縦横の比率（縦向き9:16・横向き16:9）も要求する。
/// スマホのブラウザは`width/height`の`ideal`だけではカメラの横長モードを選び、
/// 縦向きでも横長の映像を返すことがあるため、比率で切り抜かせる（2026-10-23）。
Map<String, dynamic> videoConstraintsFor({
  required bool portrait,
  bool frontCamera = true,
  bool withAspectRatio = false,
}) => {
  'facingMode': frontCamera ? 'user' : 'environment',
  'width': {'ideal': portrait ? 720 : 1280},
  'height': {'ideal': portrait ? 1280 : 720},
  if (withAspectRatio) 'aspectRatio': {'ideal': portrait ? 9 / 16 : 16 / 9},
};
