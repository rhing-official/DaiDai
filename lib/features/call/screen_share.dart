import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_webrtc/flutter_webrtc.dart';

/// 画面共有（配信）の画質（2026-11-15）。解像度（高さ）とフレームレート。
/// 高画質（1080p以上・60FPS）は極みプラン限定（無料は480p・720pで最大30FPS）。
@immutable
class ScreenShareQuality {
  const ScreenShareQuality({
    this.height = 720,
    this.fps = 30,
    this.audioOnly = false,
  });

  final int height;
  final int fps;

  /// 音声だけを共有する（映像は黒で、ほぼ通信しない）。
  final bool audioOnly;

  static const heights = [480, 720, 1080, 1440];
  static const fpsOptions = [15, 30, 60];
  static const standard = ScreenShareQuality();

  int get width => (captureHeight * 16 / 9).round();

  /// 取得する映像の高さ（音声だけの時は、最小限）。
  int get captureHeight => audioOnly ? 360 : height;

  /// 取得するフレームレート（音声だけの時は、最小限）。
  int get captureFps => audioOnly ? 5 : fps;

  /// タイルに出す表示（`720P 30FPS`）。
  String get label => audioOnly ? 'AUDIO ONLY' : '${height}P ${fps}FPS';

  /// 極み限定の画質か（1080p以上、または60FPS）。
  bool get isHigh => !audioOnly && (height > 720 || fps > 30);

  /// 無料でも使える画質か。
  bool allowedFor({required bool kiwami}) => kiwami || !isHigh;

  /// 送信の上限ビットレート（bps）。
  int get maxBitrate {
    if (audioOnly) return 100000;
    final base = switch (height) {
      <= 480 => 1500000,
      <= 720 => 2500000,
      <= 1080 => 5000000,
      _ => 9000000,
    };
    // 60FPSは、動きが滑らかな分、帯域を1.5倍まで許す。15FPSは少なくて済む。
    return switch (fps) {
      >= 60 => (base * 1.5).round(),
      <= 15 => (base * 0.7).round(),
      _ => base,
    };
  }

  ScreenShareQuality copyWith({int? height, int? fps, bool? audioOnly}) =>
      ScreenShareQuality(
        height: height ?? this.height,
        fps: fps ?? this.fps,
        audioOnly: audioOnly ?? this.audioOnly,
      );

  @override
  bool operator ==(Object other) =>
      other is ScreenShareQuality &&
      other.height == height &&
      other.fps == fps &&
      other.audioOnly == audioOnly;

  @override
  int get hashCode => Object.hash(height, fps, audioOnly);
}

/// 画面共有の取得（ブラウザの`getDisplayMedia`）。配信元の選択画面はブラウザが出す。
class ScreenShareCapture {
  /// 画面共有に対応しているか。WebのPC（スマホのブラウザは`getDisplayMedia`が無い）と、
  /// ネイティブのAndroid（映像のみ。音声は取れない）。
  static bool get isSupported {
    if (isNativeAndroid) return true;
    if (!kIsWeb) return false;
    return switch (defaultTargetPlatform) {
      TargetPlatform.android || TargetPlatform.iOS => false,
      _ => true,
    };
  }

  /// ネイティブのAndroidか（画面共有は映像のみ。音声・音声だけ共有・タブの案内は出さない）。
  static bool get isNativeAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static const _channel = MethodChannel('jp.rhing.daidai/pip');

  /// Androidで、画面共有が終わったことを前面サービスへ伝える（`mediaProjection`型を外す）。
  /// 開始側は、許可の直後にネイティブ側のフックが行う。
  static Future<void> notifyNativeStopped() async {
    if (!isNativeAndroid) return;
    try {
      await _channel.invokeMethod<void>('setScreenShareActive', {
        'active': false,
      });
    } catch (_) {}
  }

  /// `getDisplayMedia`の制約。
  static Map<String, dynamic> constraints(
    ScreenShareQuality quality, {
    required bool shareAudio,
  }) => isNativeAndroid
      // ネイティブのAndroidは、制約をほぼ解釈せず、画面の大きさのまま映像だけを取る。
      ? {
          'video': {'frameRate': quality.captureFps},
          'audio': false,
        }
      : {
          'video': {
            'width': {'ideal': quality.width},
            'height': {'ideal': quality.captureHeight},
            'frameRate': {'ideal': quality.captureFps},
          },
          // 音声は、マイク向けの加工（エコー除去・ノイズ抑制・自動音量）を掛けずに取る。
          'audio': shareAudio
              ? {
                  'echoCancellation': false,
                  'noiseSuppression': false,
                  'autoGainControl': false,
                }
              : false,
          // Chromeの選択画面で、システム音声の共有を出す。自分のタブは選択肢から外す（映像が自分を
          // 映し続ける無限鏡になる為）。非対応のブラウザは、知らない項目を無視する。
          if (shareAudio) 'systemAudio': 'include',
          'selfBrowserSurface': 'exclude',
          'surfaceSwitching': 'include',
        };

  /// 取得した画面の種類（`browser`＝タブ、`window`、`monitor`。分からなければ`unknown`）。
  static String surfaceOf(MediaStream stream) {
    try {
      final settings = stream.getVideoTracks().firstOrNull?.getSettings();
      return '${settings?['displaySurface'] ?? 'unknown'}';
    } catch (_) {
      return 'unknown';
    }
  }

  /// 配信元を選ばせて取得する。選択をやめた（キャンセル）・許可されなかった時はnull。
  static Future<MediaStream?> start(
    ScreenShareQuality quality, {
    required bool shareAudio,
  }) async {
    try {
      final stream = await navigator.mediaDevices.getDisplayMedia(
        constraints(quality, shareAudio: shareAudio),
      );
      applyAudioOnly(stream, quality);
      return stream;
    } catch (_) {
      return null;
    }
  }

  /// 音声だけの共有では、映像のトラックを無効にして黒いフレームにする（通信がほぼ要らない）。
  static void applyAudioOnly(MediaStream stream, ScreenShareQuality quality) {
    for (final track in stream.getVideoTracks()) {
      track.enabled = !quality.audioOnly;
    }
  }

  /// 送信側に、画質に応じたビットレート・フレームレートの上限を付ける。失敗しても共有は続ける。
  static Future<void> applySenderLimits(
    RTCRtpSender sender,
    ScreenShareQuality quality,
  ) async {
    try {
      await sender.setParameters(
        RTCRtpParameters(
          encodings: [
            RTCRtpEncoding(
              maxBitrate: quality.maxBitrate,
              maxFramerate: quality.captureFps,
            ),
          ],
        ),
      );
    } catch (_) {}
  }
}
