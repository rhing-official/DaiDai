import 'package:flutter_test/flutter_test.dart';

import 'package:daidai/features/call/acquire_with_video_fallback.dart';

void main() {
  test('映像を求めて取得できれば映像つき', () async {
    final calls = <bool>[];
    final r = await acquireWithVideoFallback<String>(
      wantVideo: true,
      acquire: (video) async {
        calls.add(video);
        return video ? 'av' : 'a';
      },
    );
    expect(r.stream, 'av');
    expect(r.usedVideo, isTrue);
    expect(calls, [true]);
  });

  test('映像を求めて失敗したら、音声のみで取り直す', () async {
    final calls = <bool>[];
    final r = await acquireWithVideoFallback<String>(
      wantVideo: true,
      acquire: (video) async {
        calls.add(video);
        if (video) throw StateError('no camera');
        return 'a';
      },
    );
    expect(r.stream, 'a');
    expect(r.usedVideo, isFalse);
    expect(calls, [true, false]);
  });

  test('音声のみでも失敗したら例外のまま', () async {
    expect(
      acquireWithVideoFallback<String>(
        wantVideo: true,
        acquire: (_) async => throw StateError('no mic'),
      ),
      throwsStateError,
    );
  });

  test('映像を求めなければ最初から音声のみで1回だけ取得する', () async {
    final calls = <bool>[];
    final r = await acquireWithVideoFallback<String>(
      wantVideo: false,
      acquire: (video) async {
        calls.add(video);
        return 'a';
      },
    );
    expect(r.usedVideo, isFalse);
    expect(calls, [false]);
  });
}
