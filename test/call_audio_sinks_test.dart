import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daidai/features/call/call_audio_sinks.dart';

void main() {
  testWidgets('渡すレンダラーが無ければ何も載せない', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: CallAudioSinks(renderers: [])),
    );
    expect(
      find.descendant(
        of: find.byType(CallAudioSinks),
        matching: find.byType(IgnorePointer),
      ),
      findsNothing,
    );
  });

  group('groupAudioOnlyUserIds', () {
    test('グリッド表示: 映像オフの参加者だけ音声を鳴らす', () {
      expect(
        groupAudioOnlyUserIds(remoteIds: ['a', 'b', 'c'], videoOnIds: {'a'}),
        ['b', 'c'],
      );
    });

    test('拡大中: 拡大している映像の1人以外は、映像ありでも音声だけ鳴らす', () {
      expect(
        groupAudioOnlyUserIds(
          remoteIds: ['a', 'b', 'c'],
          videoOnIds: {'a', 'b'},
          focusedUserId: 'a',
        ),
        ['b', 'c'],
      );
    });

    test('拡大している参加者が映像オフなら、その人も音声だけ鳴らす', () {
      expect(
        groupAudioOnlyUserIds(
          remoteIds: ['a', 'b'],
          videoOnIds: {'b'},
          focusedUserId: 'a',
        ),
        ['a', 'b'],
      );
    });

    test('自分を拡大している間は、リモート全員が音声だけ', () {
      expect(
        groupAudioOnlyUserIds(
          remoteIds: ['a', 'b'],
          videoOnIds: {'a', 'b'},
          focusedUserId: 'self',
        ),
        ['a', 'b'],
      );
    });
  });
}
