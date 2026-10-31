import 'package:daidai/features/setup/initial_setup_screen.dart';
import 'package:daidai/features/setup/setup_presets.dart';
import 'package:daidai/utils/platform_info.dart';
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
import 'package:daidai/providers/notification_sound_provider.dart';
import 'package:daidai/providers/ringtone_sound_provider.dart';
import 'package:daidai/providers/send_key_mode_provider.dart';
import 'package:daidai/models/talks_list_layout_style.dart';
import 'package:daidai/providers/sticker_send_mode_provider.dart';
import 'package:daidai/providers/talks_list_layout_style_provider.dart';
import 'package:daidai/providers/text_color_provider.dart';
import 'package:daidai/providers/theme_mode_provider.dart';
import 'package:daidai/models/residence.dart';
import 'package:daidai/providers/repository_providers.dart';
import 'package:daidai/repositories/residence_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeResidenceRepository implements ResidenceRepository {
  @override
  Future<Residence?> getResidence(String userId) async => null;

  @override
  Future<void> saveResidence(String userId, Residence residence) async {}
}

Future<ProviderContainer> _pumpSetup(
  WidgetTester tester, {
  required VoidCallback onCompleted,
  Size size = const Size(1000, 800),
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = ProviderContainer(
    overrides: [
      initialAppLocaleProvider.overrideWithValue(AppLocale.japanese),
      initialAccentColorProvider.overrideWithValue(const Color(0xFFF08300)),
      initialTextColorLightProvider.overrideWithValue(kDefaultTextColorLight),
      initialTextColorDarkProvider.overrideWithValue(kDefaultTextColorDark),
      initialCustomAccentColorsProvider.overrideWithValue(const []),
      initialRemovedDefaultColorPresetsProvider.overrideWithValue(const {}),
      initialGekigaBackgroundColorProvider.overrideWithValue(
        const Color(0xFFC1272D),
      ),
      initialSendKeyModeProvider.overrideWithValue(SendKeyMode.enterToSend),
      initialStickerSendModeProvider.overrideWithValue(StickerSendMode.line),
      initialDraftSyncEnabledProvider.overrideWithValue(true),
      initialMessageTimeFormatProvider.overrideWithValue(MessageTimeFormat.h24),
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
      // 通知ページ（音設定）が参照する、端末に保存されたカスタム音源・通知音。
      initialRingtoneCustomSoundProvider.overrideWithValue(null),
      initialCallingCustomSoundProvider.overrideWithValue(null),
      initialNotificationSoundProvider.overrideWithValue(null),
      initialNotificationCustomSoundProvider.overrideWithValue(null),
      residenceRepositoryProvider.overrideWithValue(_FakeResidenceRepository()),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: InitialSetupScreen(
          onCompleted: onCompleted,
          previewBuilder: (focus) => Text('preview:${focus.name}'),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  test('語らい一覧のステップは、コンピューターでは飛ばす', () {
    expect(
      setupStepsFor(DeviceClass.computer),
      isNot(contains(SetupStep.talksList)),
    );
    expect(setupStepsFor(DeviceClass.phone), contains(SetupStep.talksList));
    expect(setupStepsFor(DeviceClass.phone).first, SetupStep.preset);
  });

  testWidgets('次へ・戻るで進退し、最後は完了で終わる', (tester) async {
    var completed = 0;
    await _pumpSetup(tester, onCompleted: () => completed++);
    final total = setupStepsFor(
      classifyDevice(tester.element(find.byType(Scaffold))),
    ).length;
    expect(find.text('1 / $total'), findsOneWidget);
    // 先頭では戻るが無効。
    final back = tester.widget<TextButton>(
      find.widgetWithText(TextButton, '戻る'),
    );
    expect(back.onPressed, isNull);

    await tester.tap(find.text('次へ'));
    await tester.pumpAndSettle();
    expect(find.text('2 / $total'), findsOneWidget);
    await tester.tap(find.text('戻る'));
    await tester.pumpAndSettle();
    expect(find.text('1 / $total'), findsOneWidget);

    for (var i = 1; i < total; i++) {
      await tester.tap(find.text('次へ'));
      await tester.pumpAndSettle();
    }
    expect(find.text('完了'), findsOneWidget);
    expect(completed, 0);
    await tester.tap(find.text('完了'));
    await tester.pumpAndSettle();
    expect(completed, 1);
  });

  testWidgets('あとで、で終わる', (tester) async {
    var completed = 0;
    await _pumpSetup(tester, onCompleted: () => completed++);
    await tester.tap(find.text('あとで'));
    await tester.pumpAndSettle();
    expect(completed, 1);
  });

  testWidgets('おすすめを選ぶと、設定がまとめて変わる', (tester) async {
    final container = await _pumpSetup(tester, onCompleted: () {});
    await tester.tap(find.text('くっきり'));
    await tester.pumpAndSettle();
    expect(container.read(appUiStyleProvider), AppUiStyle.flat);
    expect(container.read(appThemeModeProvider), ThemeMode.light);
    expect(container.read(fontDesignProvider), FontDesign.notoSansJp);
    expect(container.read(chatLayoutStyleProvider), ChatLayoutStyle.sideBySide);
    expect(container.read(accentColorProvider), kSetupPresets[1].accent);

    await tester.tap(find.text('遊び心'));
    await tester.pumpAndSettle();
    expect(container.read(appUiStyleProvider), AppUiStyle.gekiga);
  });

  testWidgets('ステップごとに、背景のプレビューの焦点が変わる', (tester) async {
    await _pumpSetup(tester, onCompleted: () {});
    expect(find.text('preview:talksList'), findsOneWidget);
    await tester.tap(find.text('次へ'));
    await tester.pumpAndSettle();
    expect(find.text('preview:chat'), findsOneWidget);
  });
}
