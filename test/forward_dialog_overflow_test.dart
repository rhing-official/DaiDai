import 'package:daidai/features/chat/forward_target_dialog.dart';
import 'package:daidai/utils/forward_message.dart';
import 'package:daidai/models/direct_message.dart';
import 'package:daidai/models/dm_room.dart';
import 'package:daidai/models/group.dart';
import 'package:daidai/providers/block_providers.dart';
import 'package:daidai/repositories/direct_message_repository.dart';
import 'package:daidai/repositories/group_repository.dart';
import 'package:daidai/models/calendar_system.dart';
import 'package:daidai/models/calendar_week_start.dart';
import 'package:daidai/providers/calendar_system_provider.dart';
import 'package:daidai/providers/calendar_week_start_provider.dart';
import 'package:daidai/providers/holiday_settings_provider.dart';
import 'package:daidai/l10n/app_locale.dart';
import 'package:daidai/models/app_ui_style.dart';
import 'package:daidai/models/chat_layout_style.dart';
import 'package:daidai/models/font_design.dart';
import 'package:daidai/models/message_time_format.dart';
import 'package:daidai/providers/accent_color_provider.dart';
import 'package:daidai/providers/app_locale_provider.dart';
import 'package:daidai/providers/app_ui_style_provider.dart';
import 'package:daidai/providers/calling_sound_provider.dart';
import 'package:daidai/models/slide_transition_style.dart';
import 'package:daidai/providers/chat_layout_style_provider.dart';
import 'package:daidai/providers/slide_transition_style_provider.dart';
import 'package:daidai/providers/custom_accent_colors_provider.dart';
import 'package:daidai/providers/draft_sync_enabled_provider.dart';
import 'package:daidai/providers/font_design_provider.dart';
import 'package:daidai/providers/gekiga_background_color_provider.dart';
import 'package:daidai/models/send_key_mode.dart';
import 'package:daidai/models/sticker_send_mode.dart';
import 'package:daidai/providers/message_time_format_provider.dart';
import 'package:daidai/providers/removed_default_color_presets_provider.dart';
import 'package:daidai/providers/notification_sound_provider.dart';
import 'package:daidai/providers/ringtone_sound_provider.dart';
import 'package:daidai/providers/send_key_mode_provider.dart';
import 'package:daidai/models/talks_list_layout_style.dart';
import 'package:daidai/providers/sticker_send_mode_provider.dart';
import 'package:daidai/providers/talks_list_layout_style_provider.dart';
import 'package:daidai/providers/text_color_provider.dart';
import 'package:daidai/providers/theme_mode_provider.dart';
import 'package:daidai/providers/repository_providers.dart';
import 'package:daidai/theme/gekiga/gekiga_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeDm implements DirectMessageRepository {
  @override
  Stream<List<DirectMessage>> watchDirectMessages(String userId) =>
      Stream.value(const [
        DirectMessage(
          dmId: 'd1',
          participants: ['u1', 'u2'],
          participantRhingSeeds: {'u1': 'me', 'u2': 'si_kuria_long_name'},
        ),
      ]);
  @override
  Stream<List<DmRoom>> watchRooms({
    required String dmId,
    required String userId,
  }) => Stream.value(const []);
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _FakeGroup implements GroupRepository {
  @override
  Stream<List<Group>> watchGroups(String userId) => Stream.value(const [
    Group(
      groupId: 'g1',
      name: '終焉と消失',
      ownerId: 'u1',
      memberIds: ['u1'],
      memberRoles: {},
    ),
  ]);
  @override
  Stream<List<Room>> watchRooms({
    required String groupId,
    required String userId,
  }) => Stream.value(const [
    Room(roomId: 'r1', groupId: 'g1', name: 'ワッカさん', memberIds: ['u1']),
    Room(roomId: 'r2', groupId: 'g1', name: 'ルールー', memberIds: ['u1']),
  ]);
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

// 転送先ポップアップが、どの画面幅・UIスタイルでもはみ出さない回帰テスト
// （2026-11-06。劇画はテーマで`Dialog`の最大幅が400pxに制限されており、横に広い画面の2ペイン
// （340+余白+プレビュー）がその幅に収まらず「RIGHT OVERFLOWED」になった）。
void main() {
  for (final style in [AppUiStyle.gekiga, AppUiStyle.flat])
    for (final w in [
      320.0,
      360.0,
      400.0,
      423.0,
      500.0,
      700.0,
      759.0,
      760.0,
      800.0,
      848.0,
      1000.0,
    ]) {
      testWidgets('転送先ポップアップ（幅$w・$style）がはみ出さない', (tester) async {
        SharedPreferences.setMockInitialValues({});
        tester.view.physicalSize = Size(w, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              initialAppLocaleProvider.overrideWithValue(AppLocale.japanese),
              initialAccentColorProvider.overrideWithValue(
                const Color(0xFFF08300),
              ),
              initialTextColorLightProvider.overrideWithValue(
                kDefaultTextColorLight,
              ),
              initialTextColorDarkProvider.overrideWithValue(
                kDefaultTextColorDark,
              ),
              initialCustomAccentColorsProvider.overrideWithValue(const []),
              initialRemovedDefaultColorPresetsProvider.overrideWithValue(
                const {},
              ),
              initialGekigaBackgroundColorProvider.overrideWithValue(
                const Color(0xFFC1272D),
              ),
              initialSendKeyModeProvider.overrideWithValue(
                SendKeyMode.enterToSend,
              ),
              initialStickerSendModeProvider.overrideWithValue(
                StickerSendMode.line,
              ),
              initialDraftSyncEnabledProvider.overrideWithValue(true),
              initialMessageTimeFormatProvider.overrideWithValue(
                MessageTimeFormat.h24,
              ),
              initialSlideTransitionStyleProvider.overrideWithValue(
                SlideTransitionStyle.slideBlur,
              ),
              initialChatLayoutStyleProvider.overrideWithValue(
                ChatLayoutStyle.sideBySide,
              ),
              initialTalksListLayoutStyleProvider.overrideWithValue(
                TalksListLayoutStyle.standard,
              ),
              initialAppThemeModeProvider.overrideWithValue(ThemeMode.system),
              initialCalendarWeekStartProvider.overrideWithValue(
                CalendarWeekStart.sunday,
              ),
              initialCalendarSystemProvider.overrideWithValue(
                CalendarSystem.gregorian,
              ),
              initialHolidaySettingsProvider.overrideWithValue(
                const HolidaySettings(),
              ),
              initialAppUiStyleProvider.overrideWithValue(style),
              initialFontDesignProvider.overrideWithValue(
                FontDesign.hannariMincho,
              ),
              initialRingtoneSoundProvider.overrideWithValue(null),
              initialCallingSoundProvider.overrideWithValue(null),
              // 通知ページ（音設定）が参照する、端末に保存されたカスタム音源・通知音。
              initialRingtoneCustomSoundProvider.overrideWithValue(null),
              initialCallingCustomSoundProvider.overrideWithValue(null),
              initialNotificationSoundProvider.overrideWithValue(null),
              initialNotificationCustomSoundProvider.overrideWithValue(null),

              directMessageRepositoryProvider.overrideWithValue(_FakeDm()),
              groupRepositoryProvider.overrideWithValue(_FakeGroup()),
              blockedUserIdsProvider.overrideWith(
                (ref, id) => Stream.value(<String>{}),
              ),
            ],
            child: MaterialApp(
              theme: style == AppUiStyle.gekiga
                  ? GekigaTheme.build(const Color(0xFFC1272D))
                  : null,
              home: Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () => showForwardTargetDialog(
                      context,
                      currentUserId: 'u1',
                      preview: const ForwardPreview(text: 'こんにちは'),
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
}
