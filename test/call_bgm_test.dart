import 'package:daidai/features/call/bgm/bgm_storage.dart';
import 'package:daidai/features/call/bgm/call_bgm.dart';
import 'package:daidai/features/call/bgm/call_bgm_sheet.dart';
import 'package:daidai/l10n/app_locale.dart';
import 'package:daidai/l10n/strings.dart';
import 'package:daidai/models/group_call.dart';
import 'package:daidai/providers/app_locale_provider.dart';
import 'package:daidai/models/group_role.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('CallParticipant: bgmTitleを読み書き出来る（無ければnull）', () {
    final withBgm = CallParticipant.fromJson('u1', {
      'rhingSeed': 'a',
      'bgmTitle': '曲A',
    });
    expect(withBgm.bgmTitle, '曲A');
    expect(withBgm.toJson()['bgmTitle'], '曲A');

    final without = CallParticipant.fromJson('u2', {'rhingSeed': 'b'});
    expect(without.bgmTitle, isNull);
    expect(without.toJson().containsKey('bgmTitle'), isFalse);
  });

  test('GroupPermission.playBgm: 権限一覧に含まれ、日英のラベルがある', () {
    expect(GroupPermission.all, contains(GroupPermission.playBgm));
    expect(
      Strings.of(
        AppLocale.japanese,
      ).groupPermissionLabel(GroupPermission.playBgm),
      isNot(GroupPermission.playBgm),
    );
    expect(
      Strings.of(
        AppLocale.britishEnglish,
      ).groupPermissionLabel(GroupPermission.playBgm),
      isNot(GroupPermission.playBgm),
    );
  });

  test('bgmMimeTypeFor・bgmDisplayName', () {
    expect(bgmMimeTypeFor('a.MP3'), 'audio/mpeg');
    expect(bgmMimeTypeFor('a.flac'), 'audio/flac');
    expect(bgmMimeTypeFor('noext'), 'audio/mpeg');
    expect(bgmDisplayName('my.song.mp3'), 'my.song');
    expect(bgmDisplayName('noext'), 'noext');
  });

  testWidgets('Navigatorの無い通話画面（Overlayだけ）でも、BGMのパネルが開く', (tester) async {
    final bgm = CallBgm(
      storage: createBgmStorage(),
      micTrack: () => null,
      replaceOutgoingAudio: (_) async {},
      onPlayingChanged: (_) {},
    );
    final binding = CallBgmBinding(
      bgm: bgm,
      controller: ChangeNotifier(),
      otherPlayingTitle: () => null,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          initialAppLocaleProvider.overrideWithValue(AppLocale.japanese),
        ],
        child: MaterialApp(
          home: const SizedBox.shrink(),
          // `MaterialApp.builder`の位置（Navigatorの外）に、専用のOverlayで置く。
          builder: (context, child) => Stack(
            children: [
              Positioned.fill(child: child!),
              Positioned.fill(
                child: Overlay(
                  initialEntries: [
                    OverlayEntry(
                      builder: (context) => Center(
                        child: TextButton(
                          onPressed: () => showCallBgmSheet(context, binding),
                          child: const Text('open'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(Slider), findsOneWidget);
  });
}
