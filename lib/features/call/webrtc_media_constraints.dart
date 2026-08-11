import 'package:flutter/foundation.dart';

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

Map<String, dynamic> buildVideoConstraints() => {
  'facingMode': 'user',
  'width': {'ideal': 1280},
  'height': {'ideal': 720},
};
