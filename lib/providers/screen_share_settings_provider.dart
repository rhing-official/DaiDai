import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/call/screen_share.dart';

const _heightKey = 'screenShareHeight';
const _fpsKey = 'screenShareFps';
const _audioKey = 'screenShareAudio';
const _audioOnlyKey = 'screenShareAudioOnly';
const _muteMicKey = 'screenShareMuteMic';
const _linuxMonitorKey = 'screenShareLinuxMonitor';

/// 画面共有の設定（画質・音声を共有するか、2026-11-15）。端末ごとに保存する。
class ScreenShareSettings {
  const ScreenShareSettings({
    this.quality = ScreenShareQuality.standard,
    this.shareAudio = true,
    this.muteMic = false,
    this.linuxMonitorId,
  });

  /// 画質（`audioOnly`＝音声だけの共有も、ここに含む）。
  final ScreenShareQuality quality;
  final bool shareAudio;

  /// 共有中は自分のマイクをミュートにする（音楽だけを届けたい時用）。
  final bool muteMic;

  /// Linuxのブラウザで、共有の音として取る「Monitor of …」入力のdeviceId（未選択はnull＝先頭）。
  final String? linuxMonitorId;

  /// ウィンドウ・画面全体の共有で、システム全体の音を入力デバイスとして足す（相手の声も含まれる）。

  ScreenShareSettings copyWith({
    ScreenShareQuality? quality,
    bool? shareAudio,
    bool? muteMic,
    String? linuxMonitorId,
  }) => ScreenShareSettings(
    quality: quality ?? this.quality,
    shareAudio: shareAudio ?? this.shareAudio,
    muteMic: muteMic ?? this.muteMic,
    linuxMonitorId: linuxMonitorId ?? this.linuxMonitorId,
  );
}

Future<ScreenShareSettings> loadScreenShareSettings() async {
  final prefs = await SharedPreferences.getInstance();
  final height = prefs.getInt(_heightKey);
  final fps = prefs.getInt(_fpsKey);
  return ScreenShareSettings(
    quality: ScreenShareQuality(
      height: ScreenShareQuality.heights.contains(height) ? height! : 720,
      fps: ScreenShareQuality.fpsOptions.contains(fps) ? fps! : 30,
      audioOnly: prefs.getBool(_audioOnlyKey) ?? false,
    ),
    shareAudio: prefs.getBool(_audioKey) ?? true,
    muteMic: prefs.getBool(_muteMicKey) ?? false,
    linuxMonitorId: prefs.getString(_linuxMonitorKey),
  );
}

class ScreenShareSettingsNotifier extends Notifier<ScreenShareSettings> {
  @override
  ScreenShareSettings build() {
    loadScreenShareSettings().then((value) {
      if (ref.mounted) _set(value);
    });
    return const ScreenShareSettings();
  }

  void _set(ScreenShareSettings value) {
    state = value;
    ScreenShareCapture.preferredLinuxMonitorId = value.linuxMonitorId;
  }

  Future<void> _update(ScreenShareSettings value) async {
    _set(value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_heightKey, value.quality.height);
    await prefs.setInt(_fpsKey, value.quality.fps);
    await prefs.setBool(_audioKey, value.shareAudio);
    await prefs.setBool(_audioOnlyKey, value.quality.audioOnly);
    await prefs.setBool(_muteMicKey, value.muteMic);
    final monitor = value.linuxMonitorId;
    if (monitor != null) await prefs.setString(_linuxMonitorKey, monitor);
  }

  Future<void> setQuality(ScreenShareQuality quality) =>
      _update(state.copyWith(quality: quality));

  Future<void> setShareAudio(bool value) =>
      _update(state.copyWith(shareAudio: value));

  Future<void> setLinuxMonitorId(String id) =>
      _update(state.copyWith(linuxMonitorId: id));

  Future<void> setMuteMic(bool value) =>
      _update(state.copyWith(muteMic: value));
}

final screenShareSettingsProvider =
    NotifierProvider<ScreenShareSettingsNotifier, ScreenShareSettings>(
      ScreenShareSettingsNotifier.new,
    );
