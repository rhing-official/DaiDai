import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/call/screen_share.dart';

const _heightKey = 'screenShareHeight';
const _fpsKey = 'screenShareFps';
const _audioKey = 'screenShareAudio';

/// 画面共有の設定（画質・音声を共有するか、2026-11-15）。端末ごとに保存する。
class ScreenShareSettings {
  const ScreenShareSettings({
    this.quality = ScreenShareQuality.standard,
    this.shareAudio = false,
  });

  final ScreenShareQuality quality;
  final bool shareAudio;
}

Future<ScreenShareSettings> loadScreenShareSettings() async {
  final prefs = await SharedPreferences.getInstance();
  final height = prefs.getInt(_heightKey);
  final fps = prefs.getInt(_fpsKey);
  return ScreenShareSettings(
    quality: ScreenShareQuality(
      height: ScreenShareQuality.heights.contains(height) ? height! : 720,
      fps: ScreenShareQuality.fpsOptions.contains(fps) ? fps! : 30,
    ),
    shareAudio: prefs.getBool(_audioKey) ?? false,
  );
}

class ScreenShareSettingsNotifier extends Notifier<ScreenShareSettings> {
  @override
  ScreenShareSettings build() {
    loadScreenShareSettings().then((value) {
      if (ref.mounted) state = value;
    });
    return const ScreenShareSettings();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_heightKey, state.quality.height);
    await prefs.setInt(_fpsKey, state.quality.fps);
    await prefs.setBool(_audioKey, state.shareAudio);
  }

  Future<void> setQuality(ScreenShareQuality quality) async {
    state = ScreenShareSettings(quality: quality, shareAudio: state.shareAudio);
    await _save();
  }

  Future<void> setShareAudio(bool value) async {
    state = ScreenShareSettings(quality: state.quality, shareAudio: value);
    await _save();
  }
}

final screenShareSettingsProvider =
    NotifierProvider<ScreenShareSettingsNotifier, ScreenShareSettings>(
      ScreenShareSettingsNotifier.new,
    );
