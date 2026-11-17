import 'dart:async';

import 'package:daidai/utils/resilient_rooms_stream.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const wait = Duration(milliseconds: 60);
  const retry = Duration(milliseconds: 40);

  Stream<List<String>> make(
    StreamController<RoomsSnapshot<String>> Function() open, {
    Future<List<String>> Function()? fetch,
  }) {
    return resilientRooms<String>(
      tag: 'test',
      open: () => open().stream,
      fetchServer: fetch ?? () async => throw StateError('offline'),
      serverWait: wait,
      retryDelay: retry,
      log: (_) {},
    );
  }

  test('キャッシュ由来の0件は流さず、サーバー由来が来たらそれを流す', () async {
    final source = StreamController<RoomsSnapshot<String>>();
    final events = <List<String>>[];
    final sub = make(() => source).listen(events.add);
    source.add(const RoomsSnapshot([], fromCache: true));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(events, isEmpty);
    source.add(const RoomsSnapshot(['メイン'], fromCache: false));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(events, [
      ['メイン'],
    ]);
    await sub.cancel();
  });

  test('サーバー由来の0件はそのまま流す', () async {
    final source = StreamController<RoomsSnapshot<String>>();
    final events = <List<String>>[];
    final sub = make(() => source).listen(events.add);
    source.add(const RoomsSnapshot([], fromCache: false));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(events, [<String>[]]);
    await sub.cancel();
  });

  test('キャッシュに実データがあれば、先に流す', () async {
    final source = StreamController<RoomsSnapshot<String>>();
    final events = <List<String>>[];
    final sub = make(() => source).listen(events.add);
    source.add(const RoomsSnapshot(['a'], fromCache: true));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(events, [
      ['a'],
    ]);
    await sub.cancel();
  });

  test('サーバー由来が来ないまま待ち時間が過ぎたら、サーバーから直接取る', () async {
    final source = StreamController<RoomsSnapshot<String>>();
    final events = <List<String>>[];
    final sub = make(
      () => source,
      fetch: () async => ['メイン'],
    ).listen(events.add);
    source.add(const RoomsSnapshot([], fromCache: true));
    await Future<void>.delayed(wait + const Duration(milliseconds: 40));
    expect(events, [
      ['メイン'],
    ]);
    await sub.cancel();
  });

  test('直接取れない（オフライン）ときは、キャッシュの0件を流して止まらない', () async {
    final source = StreamController<RoomsSnapshot<String>>();
    final events = <List<String>>[];
    final sub = make(() => source).listen(events.add);
    source.add(const RoomsSnapshot([], fromCache: true));
    await Future<void>.delayed(wait + const Duration(milliseconds: 40));
    expect(events, [<String>[]]);
    await sub.cancel();
  });

  test('エラーで終わったら張り直して、次の結果が流れる', () async {
    var opened = 0;
    final controllers = <StreamController<RoomsSnapshot<String>>>[];
    final events = <List<String>>[];
    final sub = make(() {
      opened++;
      final c = StreamController<RoomsSnapshot<String>>();
      controllers.add(c);
      return c;
    }).listen(events.add);
    controllers[0].addError(StateError('permission-denied'));
    await Future<void>.delayed(retry + const Duration(milliseconds: 40));
    expect(opened, 2);
    controllers[1].add(const RoomsSnapshot(['メイン'], fromCache: false));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(events, [
      ['メイン'],
    ]);
    await sub.cancel();
  });
}
