import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

/// モバイル（Android・iOS）か。スピーカー/受話口の切替ボタンを出せる環境
/// （2026-11-01）。Webとデスクトップには受話口が無いので出さない。
bool get isSpeakerToggleCapablePlatform =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

/// 出力先の名前から、Bluetooth・有線ヘッドセットなど外部のオーディオか判定する。
/// 端末ごとに名前の付き方が違うため、内蔵（スピーカー・受話口）以外を除外する
/// のではなく、外部機器に付きがちな語を含むかで見る。
bool isExternalAudioOutputLabel(String label) {
  final l = label.toLowerCase();
  const keywords = [
    'bluetooth',
    'headset',
    'headphone',
    'airpods',
    'wired',
    'usb',
    'a2dp',
    'hfp',
    'carplay',
  ];
  return keywords.any(l.contains);
}

/// 外部のオーディオに接続中か。取得できない・判定できない時はfalse（ボタンを
/// 出したままにして、切り替えられなくなるのを避ける）。
Future<bool> hasExternalAudioOutput() async {
  if (!isSpeakerToggleCapablePlatform) return false;
  try {
    final outputs = await Helper.audiooutputs;
    return outputs.any(
      (d) =>
          isExternalAudioOutputLabel(d.label) ||
          isExternalAudioOutputLabel(d.deviceId),
    );
  } catch (_) {
    return false;
  }
}
