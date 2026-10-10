import 'package:daidai/features/settings/settings_tab.dart';
import 'package:daidai/l10n/strings.dart';
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

// 管理画面の設定タブ（[ApplicationSettingsView]）は、利用者画面の設定>
// アプリケーションの項目を、パスコードロック以外そのまま表示する（2026-10-10）。
void main() {
  testWidgets('パスコードロック以外のアプリケーション設定を表示する', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

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
        ],
        child: const MaterialApp(
          home: Scaffold(body: ApplicationSettingsView()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final strings = Strings.of(AppLocale.japanese);
    expect(find.text(strings.settingsAppearance), findsOneWidget);

    // 末尾まで読み込ませた上で、時刻の表示方法は有り、パスコードロックは無いこと。
    await tester.drag(find.byType(ListView).first, const Offset(0, -5000));
    await tester.pumpAndSettle();
    expect(find.text(strings.settingsTimeFormat), findsOneWidget);
    expect(find.text(strings.settingsPasscodeLockToggleLabel), findsNothing);
  });
}
