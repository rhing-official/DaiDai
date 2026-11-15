import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:daidai/features/call/screen_share.dart';
import 'package:daidai/models/group_call.dart';
import 'package:daidai/providers/screen_share_settings_provider.dart';

void main() {
  group('画面共有の画質', () {
    test('表示・幅（16:9）・高画質の判定', () {
      const q = ScreenShareQuality(height: 720, fps: 30);
      expect(q.label, '720P 30FPS');
      expect(q.width, 1280);
      expect(q.isHigh, isFalse);
      expect(const ScreenShareQuality(height: 1080, fps: 30).isHigh, isTrue);
      expect(const ScreenShareQuality(height: 720, fps: 60).isHigh, isTrue);
    });

    test('高画質は極みだけ。無料は480p・720pで最大30FPS', () {
      const high = ScreenShareQuality(height: 1440, fps: 60);
      expect(high.allowedFor(kiwami: false), isFalse);
      expect(high.allowedFor(kiwami: true), isTrue);
      expect(ScreenShareQuality.standard.allowedFor(kiwami: false), isTrue);
      expect(
        const ScreenShareQuality(
          height: 480,
          fps: 15,
        ).allowedFor(kiwami: false),
        isTrue,
      );
    });

    test('ビットレートは解像度・FPSが上がるほど大きい', () {
      int b(int h, int f) => ScreenShareQuality(height: h, fps: f).maxBitrate;
      expect(b(480, 30), lessThan(b(720, 30)));
      expect(b(720, 30), lessThan(b(1080, 30)));
      expect(b(720, 15), lessThan(b(720, 30)));
      expect(b(720, 30), lessThan(b(720, 60)));
    });

    test('getDisplayMediaの制約に、解像度・FPS・音声が入る', () {
      final c = ScreenShareCapture.constraints(
        const ScreenShareQuality(height: 1080, fps: 60),
        shareAudio: true,
      );
      final video = c['video'] as Map;
      expect((video['height'] as Map)['ideal'], 1080);
      expect((video['frameRate'] as Map)['ideal'], 60);
      expect(c['audio'], isTrue);
    });

    test('Web以外では画面共有に対応しない', () {
      expect(ScreenShareCapture.isSupported, isFalse);
    });
  });

  test('設定の既定は720p・30FPS・音声オフで、保存した値を読み戻せる', () async {
    SharedPreferences.setMockInitialValues({});
    var s = await loadScreenShareSettings();
    expect(s.quality, ScreenShareQuality.standard);
    expect(s.shareAudio, isFalse);
    SharedPreferences.setMockInitialValues({
      'screenShareHeight': 1080,
      'screenShareFps': 60,
      'screenShareAudio': true,
      // 想定外の値は既定に戻す。
    });
    s = await loadScreenShareSettings();
    expect(s.quality.height, 1080);
    expect(s.quality.fps, 60);
    expect(s.shareAudio, isTrue);
    SharedPreferences.setMockInitialValues({'screenShareHeight': 999});
    expect((await loadScreenShareSettings()).quality.height, 720);
  });

  test('参加者の配信の画質の表示を、保存・読み込みできる', () {
    final p = CallParticipant.fromJson('u1', {
      'rhingSeed': 'seed',
      'screenLabel': '720P 30FPS',
    });
    expect(p.screenLabel, '720P 30FPS');
    expect(p.toJson()['screenLabel'], '720P 30FPS');
    expect(
      CallParticipant.fromJson('u2', {'rhingSeed': 'x'}).screenLabel,
      isNull,
    );
  });
}
