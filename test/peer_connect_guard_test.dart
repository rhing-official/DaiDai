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

  group('videoConstraintsFor', () {
    test('横向きは1280x720・16:9、縦向きは縦横を入れ替えて9:16', () {
      final land = videoConstraintsFor(portrait: false, withAspectRatio: true);
      expect((land['width'] as Map)['ideal'], 1280);
      expect((land['aspectRatio'] as Map)['ideal'], 16 / 9);
      final port = videoConstraintsFor(portrait: true, withAspectRatio: true);
      expect((port['width'] as Map)['ideal'], 720);
      expect((port['height'] as Map)['ideal'], 1280);
      expect((port['aspectRatio'] as Map)['ideal'], 9 / 16);
    });

    test('比率を要求しなければaspectRatioは付かず、背面カメラも指定できる', () {
      final c = videoConstraintsFor(portrait: false, frontCamera: false);
      expect(c.containsKey('aspectRatio'), isFalse);
      expect(c['facingMode'], 'environment');
    });
  });
}
