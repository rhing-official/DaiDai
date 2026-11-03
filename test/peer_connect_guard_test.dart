import 'package:flutter_test/flutter_test.dart';

import 'package:daidai/features/call/peer_connect_guard.dart';
import 'package:daidai/features/call/webrtc_media_constraints.dart';

void main() {
  group('PeerConnectGuard', () {
    test('同じ相手の接続処理は重複して始められず、終われば再び始められる', () {
      final guard = PeerConnectGuard();
      expect(guard.tryBegin('a'), isTrue);
      expect(guard.tryBegin('a'), isFalse);
      expect(guard.isConnecting('a'), isTrue);
      expect(guard.tryBegin('b'), isTrue);
      guard.end('a');
      expect(guard.isConnecting('a'), isFalse);
      expect(guard.tryBegin('a'), isTrue);
    });

    test('途中で退室された相手だけ中断扱いになり、次の接続では解除される', () {
      final guard = PeerConnectGuard();
      guard.tryBegin('a');
      guard.cancel('a');
      guard.cancel('zzz'); // 接続中でない相手は無視
      expect(guard.isCancelled('a'), isTrue);
      expect(guard.isCancelled('zzz'), isFalse);
      guard.end('a');
      expect(guard.tryBegin('a'), isTrue);
      expect(guard.isCancelled('a'), isFalse);
    });

    test('cancelAllは接続中の全員を中断扱いにする', () {
      final guard = PeerConnectGuard()
        ..tryBegin('a')
        ..tryBegin('b');
      guard.cancelAll();
      expect(guard.isCancelled('a'), isTrue);
      expect(guard.isCancelled('b'), isTrue);
    });
  });

  group('shouldRequestPortraitVideo', () {
    test('縦長を要求するのはモバイルOSのブラウザの縦向きだけ', () {
      bool f(bool web, bool mobile, bool portrait) =>
          shouldRequestPortraitVideo(
            isWeb: web,
            isMobileOs: mobile,
            isPortraitScreen: portrait,
          );
      expect(f(true, true, true), isTrue);
      expect(f(true, false, true), isFalse); // コンピューターの縦長ウィンドウ
      expect(f(true, true, false), isFalse);
      expect(f(false, true, true), isFalse); // アプリ版
    });
  });

  group('videoConstraintsFor', () {
    test('4:3は縦向き720x960・横向き960x720で、aspectRatioは要求しない', () {
      final land = videoConstraintsFor(portrait: false, fourThree: true);
      expect((land['width'] as Map)['ideal'], 960);
      expect((land['height'] as Map)['ideal'], 720);
      final port = videoConstraintsFor(portrait: true, fourThree: true);
      expect((port['width'] as Map)['ideal'], 720);
      expect((port['height'] as Map)['ideal'], 960);
      expect(port.containsKey('aspectRatio'), isFalse);
    });

    test('4:3でなければ従来の16:9（アプリ版）', () {
      final land = videoConstraintsFor(portrait: false);
      expect((land['width'] as Map)['ideal'], 1280);
      expect((land['height'] as Map)['ideal'], 720);
    });

    test('比率を要求しなければaspectRatioは付かず、背面カメラも指定できる', () {
      final c = videoConstraintsFor(portrait: false, frontCamera: false);
      expect(c.containsKey('aspectRatio'), isFalse);
      expect(c['facingMode'], 'environment');
    });
  });
}
