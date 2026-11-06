import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../utils/screen_orientation/screen_orientation.dart';
import 'call_log.dart';

/// getUserMedia用の音声制約。
///
/// Android実機では、入れ子になった詳細な音声制約マップ（echoCancellation等の
/// キー付きMap）が正しく解釈されず、マイクが機能しなくなる既知の不具合報告が
/// ある（flutter-webrtc issue #1972, #1433, dart-sip-ua#401）。そのため
/// Androidでは単純化した`true`指定にフォールバックし、ネイティブ側の
/// デフォルトのAEC/NS/AGCに委ねる。Web/iOS/デスクトップでは詳細な制約マップを
/// そのまま使う。
///
/// 注記: ここで指定出来るのはあくまでWebRTC標準のエコー除去・ノイズ抑制・
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
    // 環境では単に無視されるため害は無いが、効果があるとは保証されない。
    'googEchoCancellation': true,
    'googNoiseSuppression': true,
    'googAutoGainControl': true,
    'googHighpassFilter': true,
  };
}

/// カメラの映像制約。ブラウザで画面が縦向きの時は、解像度の縦横を入れ替える
/// （横長固定で要求すると、縦向きのiPad等で映像が送られなくなる不具合の対処、
/// 2026-10-22）。[frontCamera]がfalseなら背面カメラ。
///
/// [deviceId]があれば、そのカメラを優先する（映像をオフ→オンした時に直前と同じ
/// カメラ・同じ画角で取り直すため、2026-10-31）。
Map<String, dynamic> buildVideoConstraints({
  bool frontCamera = true,
  String? deviceId,
}) => videoConstraintsFor(
  portrait: shouldRequestPortraitVideo(
    isWeb: kIsWeb,
    isMobileOs:
        defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS,
    isPortraitScreen: isPortraitScreen,
  ),
  frontCamera: frontCamera,
  fourThree: kIsWeb,
  deviceId: deviceId,
);

/// 縦長の映像を要求するか。端末の向きがあるスマホ・タブレット（モバイルOS）のブラウザ
/// の縦向きだけ。コンピューターは、ウィンドウが縦長（縦向きのモニター・開発者ツールを
/// 横に開いた状態など）でも、ウェブカメラの映像は横長のまま送る（2026-11-03、
/// コンピューターで縦表示の映像が送られた不具合）。
bool shouldRequestPortraitVideo({
  required bool isWeb,
  required bool isMobileOs,
  required bool isPortraitScreen,
}) => isWeb && isMobileOs && isPortraitScreen;

/// [buildVideoConstraints]の中身（向きを引数にした純粋な関数、テスト用）。
/// [fourThree]がtrueなら、センサー全体を使う4:3（縦向き720x960・横向き960x720）を
/// 要求する。以前は9:16の比率（`aspectRatio`）を要求していたが、スマホのセンサーは
/// 4:3が基本のため一部を切り抜かれ、最初の画角がとても近くなっていた（カメラを
/// 切り替えると制約が付かず広角になった）。比率は指定せず、解像度だけで4:3にする
/// （2026-11-03）。
Map<String, dynamic> videoConstraintsFor({
  required bool portrait,
  bool frontCamera = true,
  bool fourThree = false,
  String? deviceId,
}) {
  final long = fourThree ? 960 : 1280;
  return {
    'facingMode': frontCamera ? 'user' : 'environment',
    if (deviceId != null && deviceId.isNotEmpty)
      'deviceId': {'ideal': deviceId},
    // 電池消費と発熱を抑える為、フレームレートを抑える（2026-10-31）。
    // 数値で渡す（Androidはマップ形式のideal/maxを読先ず既定値になる為）。
    'frameRate': 24,
    'width': {'ideal': portrait ? 720 : long},
    'height': {'ideal': portrait ? long : 720},
  };
}

/// 取得した映像トラックの実際の大きさ・向きを診断ログに出す（画角の確認用）。
void logVideoTrackSettings(MediaStreamTrack track, String label) {
  try {
    final s = track.getSettings();
    callLog(
      '$label video ${s['width']}x${s['height']} '
      'aspect=${s['aspectRatio']} facing=${s['facingMode']}',
    );
  } catch (_) {}
}

/// 自分のレンダラーを、念のため明示的に無音にする（自分の声を自分の端末で
/// 再生しない、2026-10-31）。Webの`<audio>`にだけ効かせる（ネイティブの`muted`は
/// 音声トラック自体を止めてしまい、相手に声が届かなくなるため呼ばない）。
void muteLocalPlayback(RTCVideoRenderer renderer) {
  if (!kIsWeb) return;
  try {
    renderer.muted = true;
  } catch (_) {
    // 音声トラックが無い（映像のみ）等。無視してよい。
  }
}

/// マイク取得後に、エコー除去が実際に有効か確認し、無効なら再要求する
/// （2026-10-31）。要求しても効かない端末（ブラウザ・OS依存）では、相手の
/// スピーカーの音を相手のマイクが拾って、自分の声が遅れて返ってくる。
/// 結果は`debugPrint`に出す。失敗しても通話は続ける。
Future<void> ensureEchoCancellation(MediaStream? stream) async {
  if (stream == null) return;
  for (final track in stream.getAudioTracks()) {
    try {
      final enabled = track.getSettings()['echoCancellation'];
      debugPrint('Call: マイクのechoCancellation=$enabled');
      if (enabled == false) {
        await track.applyConstraints({'echoCancellation': true});
        final after = track.getSettings()['echoCancellation'];
        debugPrint('Call: echoCancellation re-requested, now $after');
      }
    } catch (e) {
      debugPrint('Call: echoCancellationの確認に失敗 $e');
    }
  }
}

/// 映像トラックが前面（インカメラ）かどうか。端末が`facingMode`を報告しない場合は
/// null（2026-10-31追加）。自分のプレビューを左右反転するかの判定に使う。
bool? trackIsFrontFacing(MediaStreamTrack track) {
  try {
    final facing = track.getSettings()['facingMode'];
    if (facing == 'user') return true;
    if (facing == 'environment') return false;
  } catch (_) {}
  return null;
}

/// 映像トラックを出しているカメラの`deviceId`。取れなければnull。
String? trackDeviceId(MediaStreamTrack track) {
  try {
    final id = track.getSettings()['deviceId'];
    if (id is String && id.isNotEmpty) return id;
  } catch (_) {}
  return null;
}
