import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

/// 画面共有（配信）の画質（2026-11-15）。解像度（高さ）とフレームレート。
/// 高画質（1080p以上・60FPS）は極みプラン限定（無料は480p・720pで最大30FPS）。
@immutable
class ScreenShareQuality {
  const ScreenShareQuality({this.height = 720, this.fps = 30});

  final int height;
  final int fps;

  static const heights = [480, 720, 1080, 1440];
  static const fpsOptions = [15, 30, 60];
  static const standard = ScreenShareQuality();

  int get width => (height * 16 / 9).round();

  /// タイルに出す表示（`720P 30FPS`）。
  String get label => '${height}P ${fps}FPS';

  /// 極み限定の画質か（1080p以上、または60FPS）。
  bool get isHigh => height > 720 || fps > 30;

  /// 無料でも使える画質か。
  bool allowedFor({required bool kiwami}) => kiwami || !isHigh;

  /// 送信の上限ビットレート（bps）。
  int get maxBitrate {
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

  ScreenShareQuality copyWith({int? height, int? fps}) =>
      ScreenShareQuality(height: height ?? this.height, fps: fps ?? this.fps);

  @override
  bool operator ==(Object other) =>
      other is ScreenShareQuality && other.height == height && other.fps == fps;

  @override
  int get hashCode => Object.hash(height, fps);
}

/// 画面共有の取得（ブラウザの`getDisplayMedia`）。配信元の選択画面はブラウザが出す。
class ScreenShareCapture {
  /// 画面共有に対応しているか（今はWebのPC。スマホのブラウザは`getDisplayMedia`が無い）。
  static bool get isSupported {
    if (!kIsWeb) return false;
    return switch (defaultTargetPlatform) {
      TargetPlatform.android || TargetPlatform.iOS => false,
      _ => true,
    };
  }

  /// `getDisplayMedia`の制約。
  static Map<String, dynamic> constraints(
    ScreenShareQuality quality, {
    required bool shareAudio,
  }) => {
    'video': {
      'width': {'ideal': quality.width},
      'height': {'ideal': quality.height},
      'frameRate': {'ideal': quality.fps},
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
      return await navigator.mediaDevices.getDisplayMedia(
        constraints(quality, shareAudio: shareAudio),
      );
    } catch (_) {
      return null;
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
              maxFramerate: quality.fps,
            ),
          ],
        ),
      );
    } catch (_) {}
  }
}
