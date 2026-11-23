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
import 'package:daidai/providers/theme_mode_provider.dart';
import 'package:daidai/providers/repository_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeDm2 implements DirectMessageRepository {
  @override
  Stream<List<DirectMessage>> watchDirectMessages(String userId) =>
      Stream.value(const [
        DirectMessage(
          dmId: 'd1',
          participants: ['u1', 'u2'],
          participantRhingSeeds: {'u1': 'me', 'u2': 'friend'},
          roomsEnabled: true,
        ),
      ]);
  @override
  Stream<List<DmRoom>> watchRooms({
    required String dmId,
    required String userId,
  }) => Stream.value(const [
    DmRoom(roomId: 'a', dmId: 'd1', name: '雑談', participants: ['u1', 'u2']),
    DmRoom(roomId: 'b', dmId: 'd1', name: '仕事', participants: ['u1', 'u2']),
  ]);
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _FakeDm3 extends _FakeDm2 {
  @override
  Stream<List<DirectMessage>> watchDirectMessages(String userId) =>
      Stream.value(const [
        DirectMessage(
          dmId: 'd1',
          participants: ['u1', 'u2'],
          participantRhingSeeds: {'u1': 'me', 'u2': 'friend'},
        ),
      ]);
  @override
  Stream<List<DmRoom>> watchRooms({
    required String dmId,
    required String userId,
  }) => Stream.value(const [
    DmRoom(roomId: 'a', dmId: 'd1', name: '雑談', participants: ['u1', 'u2']),
  ]);
}

class _FakeGroup2 implements GroupRepository {
  @override
  Stream<List<Group>> watchGroups(String userId) => Stream.value(const []);
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

// 一対でも、寄合が複数なら行の下に寄合が並び、選んだ寄合が転送先になる（2026-11-15）。
void main() {
  testWidgets('一対の寄合を選んで転送先にできる', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    ForwardTarget? picked;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          initialAppLocaleProvider.overrideWithValue(AppLocale.japanese),
          initialAccentColorProvider.overrideWithValue(const Color(0xFFF08300)),
          initialCustomAccentColorsProvider.overrideWithValue(const []),
          initialRemovedDefaultColorPresetsProvider.overrideWithValue(const {}),
          initialGekigaBackgroundColorProvider.overrideWithValue(
            const Color(0xFFC1272D),
          ),
          initialSendKeyModeProvider.overrideWithValue(SendKeyMode.enterToSend),
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
          initialTalksListLayoutStyleWideProvider.overrideWithValue(
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
          initialAppUiStyleProvider.overrideWithValue(AppUiStyle.flat),
          initialFontDesignProvider.overrideWithValue(FontDesign.hannariMincho),
          initialRingtoneSoundProvider.overrideWithValue(null),
          initialCallingSoundProvider.overrideWithValue(null),
          // 通知ページ（音設定）が参照する、端末に保存されたカスタム音源・通知音。
          initialRingtoneCustomSoundProvider.overrideWithValue(null),
          initialCallingCustomSoundProvider.overrideWithValue(null),
          initialNotificationSoundProvider.overrideWithValue(null),
          initialNotificationCustomSoundProvider.overrideWithValue(null),

          directMessageRepositoryProvider.overrideWithValue(_FakeDm2()),
          groupRepositoryProvider.overrideWithValue(_FakeGroup2()),
          blockedUserIdsProvider.overrideWith(
            (ref, id) => Stream.value(<String>{}),
          ),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async => picked = await showForwardTargetDialog(
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
    // 寄合はまだ畳まれている。一対の行を押すと、寄合が並ぶ。
    expect(find.text('雑談'), findsNothing);
    await tester.tap(find.textContaining('friend'));
    await tester.pumpAndSettle();
    expect(find.text('雑談'), findsOneWidget);
    expect(find.text('仕事'), findsOneWidget);
    await tester.tap(find.text('仕事'));
    await tester.pumpAndSettle();
    expect(picked?.conversationId, 'd1');
    expect(picked?.roomId, 'b');
  });

  testWidgets('寄合機能オフの一対は行を押すだけで転送先になる', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    ForwardTarget? picked;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          initialAppLocaleProvider.overrideWithValue(AppLocale.japanese),
          initialAccentColorProvider.overrideWithValue(const Color(0xFFF08300)),
          initialCustomAccentColorsProvider.overrideWithValue(const []),
          initialRemovedDefaultColorPresetsProvider.overrideWithValue(const {}),
          initialGekigaBackgroundColorProvider.overrideWithValue(
            const Color(0xFFC1272D),
          ),
          initialSendKeyModeProvider.overrideWithValue(SendKeyMode.enterToSend),
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
          initialTalksListLayoutStyleWideProvider.overrideWithValue(
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
          initialAppUiStyleProvider.overrideWithValue(AppUiStyle.flat),
          initialFontDesignProvider.overrideWithValue(FontDesign.hannariMincho),
          initialRingtoneSoundProvider.overrideWithValue(null),
          initialCallingSoundProvider.overrideWithValue(null),
          // 通知ページ（音設定）が参照する、端末に保存されたカスタム音源・通知音。
          initialRingtoneCustomSoundProvider.overrideWithValue(null),
          initialCallingCustomSoundProvider.overrideWithValue(null),
          initialNotificationSoundProvider.overrideWithValue(null),
          initialNotificationCustomSoundProvider.overrideWithValue(null),

          directMessageRepositoryProvider.overrideWithValue(_FakeDm3()),
          groupRepositoryProvider.overrideWithValue(_FakeGroup2()),
          blockedUserIdsProvider.overrideWith(
            (ref, id) => Stream.value(<String>{}),
          ),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async => picked = await showForwardTargetDialog(
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
    await tester.tap(find.textContaining('friend'));
    await tester.pumpAndSettle();
    expect(picked?.conversationId, 'd1');
    expect(picked?.roomId, 'a');
  });
}
