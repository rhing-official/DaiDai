import 'package:daidai/features/chat/announcement_screen.dart';
import 'package:daidai/models/announcement.dart';
import 'package:daidai/models/app_user.dart';
import 'package:daidai/models/message.dart';
import 'package:daidai/models/official_profile.dart';
import 'package:daidai/providers/repository_providers.dart';
import 'package:daidai/repositories/announcement_repository.dart';
import 'package:daidai/utils/reserved_rhing_seeds.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:daidai/l10n/app_locale.dart';
import 'package:daidai/models/app_ui_style.dart';
import 'package:daidai/models/chat_layout_style.dart';
import 'package:daidai/models/font_design.dart';
import 'package:daidai/models/message_time_format.dart';
import 'package:daidai/providers/accent_color_provider.dart';
import 'package:daidai/providers/app_locale_provider.dart';
import 'package:daidai/providers/app_ui_style_provider.dart';
import 'package:daidai/providers/calling_sound_provider.dart';
import 'package:daidai/providers/chat_layout_style_provider.dart';
import 'package:daidai/providers/custom_accent_colors_provider.dart';
import 'package:daidai/providers/draft_sync_enabled_provider.dart';
import 'package:daidai/providers/font_design_provider.dart';
import 'package:daidai/providers/gekiga_background_color_provider.dart';
import 'package:daidai/models/send_key_mode.dart';
import 'package:daidai/models/sticker_send_mode.dart';
import 'package:daidai/providers/message_time_format_provider.dart';
import 'package:daidai/providers/removed_default_color_presets_provider.dart';
import 'package:daidai/providers/ringtone_sound_provider.dart';
import 'package:daidai/providers/send_key_mode_provider.dart';
import 'package:daidai/models/talks_list_layout_style.dart';
import 'package:daidai/providers/sticker_send_mode_provider.dart';
import 'package:daidai/providers/talks_list_layout_style_provider.dart';
import 'package:daidai/providers/text_color_provider.dart';
import 'package:daidai/providers/theme_mode_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeAnnouncementRepository implements AnnouncementRepository {
  _FakeAnnouncementRepository(this.messages);

  final List<Message> messages;

  @override
  Stream<List<Message>> watchAnnouncementMessages() => Stream.value(messages);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// お便りは住人ではなく`announcements`・`system/official`という「そこにある物」
// （2026-10-10）。表示では`users`を引かず、返信欄も出さない。
void main() {
  test('announcementToMessage: 発信元の名前・アイコンつきのMessageに写す', () {
    final message = announcementToMessage(
      Announcement(
        id: 'a1',
        content: 'こんにちは',
        createdAt: Timestamp.fromDate(DateTime(2026, 10, 10)),
      ),
      const OfficialProfile(name: 'お便り', iconUrl: 'https://example.com/i.png'),
    );
    expect(message.senderId, OfficialProfile.senderId);
    expect(message.senderId.startsWith('system:'), isTrue);
    expect(message.botName, 'お便り');
    expect(message.botIconUrl, 'https://example.com/i.png');
    expect(message.content, 'こんにちは');
  });

  test('OfficialProfile: 未作成なら既定の名前、空の名前も既定に戻す', () {
    expect(OfficialProfile.fromJson(null).name, OfficialProfile.defaultName);
    expect(
      OfficialProfile.fromJson({'name': ''}).name,
      OfficialProfile.defaultName,
    );
    expect(OfficialProfile.fromJson({'name': '運営'}).name, '運営');
  });

  test('予約済みのRhing Seed（大文字小文字・前後の空白は無視）', () {
    expect(isReservedRhingSeed('tayori'), isTrue);
    expect(isReservedRhingSeed(' Tayori '), isTrue);
    expect(isReservedRhingSeed('official'), isTrue);
    expect(isReservedRhingSeed('taro'), isFalse);
  });

  testWidgets('お便り画面は配信を表示し、usersを引かず、入力欄も出さない', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final messages = [
      announcementToMessage(
        const Announcement(id: 'a1', content: 'メンテナンスのお知らせ'),
        const OfficialProfile(),
      ),
    ];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          initialAppLocaleProvider.overrideWithValue(AppLocale.japanese),
          initialAccentColorProvider.overrideWithValue(const Color(0xFFF08300)),
          initialTextColorLightProvider.overrideWithValue(
            kDefaultTextColorLight,
          ),
          initialTextColorDarkProvider.overrideWithValue(kDefaultTextColorDark),
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
          initialChatLayoutStyleProvider.overrideWithValue(
            ChatLayoutStyle.sideBySide,
          ),
          initialTalksListLayoutStyleProvider.overrideWithValue(
            TalksListLayoutStyle.standard,
          ),
          initialAppThemeModeProvider.overrideWithValue(ThemeMode.system),
          initialAppUiStyleProvider.overrideWithValue(AppUiStyle.flat),
          initialFontDesignProvider.overrideWithValue(FontDesign.hannariMincho),
          initialRingtoneSoundProvider.overrideWithValue(null),
          initialCallingSoundProvider.overrideWithValue(null),
          announcementRepositoryProvider.overrideWithValue(
            _FakeAnnouncementRepository(messages),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: AnnouncementScreen(
              currentUser: AppUser(userId: 'u1', rhingSeed: 'taro'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('メンテナンスのお知らせ'), findsOneWidget);
    expect(find.text('お便り'), findsWidgets);
    expect(find.byType(TextField), findsNothing);
  });
}
