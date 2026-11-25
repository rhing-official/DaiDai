import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

/// モバイル（Android・iOS）か。スピーカー/受話口の切替ボタンを出せる環境
/// （2026-11-01）。Webとデスクトップには受話口が無いので出さない。
bool get isSpeakerToggleCapablePlatform =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

/// 出力先の名前から、Bluetooth・有線ヘッドセットなど外部のオーディオか判定する。
/// 端末毎に名前の付き方が違うため、内蔵（スピーカー・受話口）以外を除外する
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

/// 外部のオーディオに接続中か。取得出来ない・判定出来ない時はfalse（ボタンを
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

/// 通話中に、映像のオン（自分・相手）や画面共有の開始（自分・相手）があった時に、スピーカーへ
/// 自動で切り替えるか（2026-11-25）。ビデオ通話はスピーカーから始まるのと同じく、画面を見る
/// 姿勢になるため。既にスピーカーなら何もしない。通話中に手動で切り替えた（受話口を選んだ）後は、
/// その選択を壊さないよう、以後は自動で切り替えない（1回の通話につき、自動の切り替えは多くて1回）。
/// 映像・共有が終わっても、受話口へは戻さない。
bool shouldAutoSpeaker({required bool speakerOn, required bool manuallySet}) =>
    !speakerOn && !manuallySet;
