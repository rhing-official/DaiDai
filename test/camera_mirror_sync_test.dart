import 'package:daidai/features/call/camera_mirror_sync.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('信号が来なければフォールバックの時間で確定する', () {
    fakeAsync((async) {
      var settled = 0;
      final race = MirrorSyncRace(fallback: const Duration(milliseconds: 450));
      race.start(() => settled++);
      async.elapse(const Duration(milliseconds: 449));
      expect(settled, 0);
      async.elapse(const Duration(milliseconds: 1));
      expect(settled, 1);
    });
  });

  test('onResizeが先に来ればそれで確定し、後続のタイマーは無視される', () {
    fakeAsync((async) {
      var settled = 0;
      final race = MirrorSyncRace(fallback: const Duration(milliseconds: 450));
      race.start(() => settled++);
      async.elapse(const Duration(milliseconds: 100));
      race.signalResize?.call();
      expect(settled, 1);
      async.elapse(const Duration(milliseconds: 1000));
      expect(settled, 1);
    });
  });

  test('onFirstFrameRenderedが先に来ても確定し、2回目の信号は無視される', () {
    fakeAsync((async) {
      var settled = 0;
      final race = MirrorSyncRace();
      race.start(() => settled++);
      race.signalFirstFrame?.call();
      race.signalResize?.call();
      expect(settled, 1);
    });
  });

  test('連続切替: start()の再呼び出しは前の競走を確定させずに止める', () {
    fakeAsync((async) {
      final log = <String>[];
      final race = MirrorSyncRace();
      race.start(() => log.add('A'));
      async.elapse(const Duration(milliseconds: 100));
      race.start(() => log.add('B'));
      async.elapse(const Duration(milliseconds: 450));
      expect(log, ['B']);
    });
  });

  test('cancel()は確定させずに止める（dispose相当）', () {
    fakeAsync((async) {
      var settled = 0;
      final race = MirrorSyncRace();
      race.start(() => settled++);
      race.cancel();
      async.elapse(const Duration(seconds: 1));
      expect(settled, 0);
      expect(race.signalResize, isNull);
      expect(race.signalFirstFrame, isNull);
    });
  });
}
