import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:google_fonts/google_fonts.dart';

import 'firebase_options.dart';
import 'l10n/app_locale.dart';
import 'models/app_ui_style.dart';
import 'providers/accent_color_provider.dart';
import 'providers/app_locale_provider.dart';
import 'providers/app_ui_style_provider.dart';
import 'providers/chat_layout_style_provider.dart';
import 'providers/draft_sync_enabled_provider.dart';
import 'providers/gekiga_background_color_provider.dart';
import 'providers/message_time_format_provider.dart';
import 'providers/send_key_mode_provider.dart';
import 'providers/sticker_send_mode_provider.dart';
import 'providers/terminology_style_provider.dart';
import 'providers/theme_mode_provider.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';
import 'theme/gekiga/gekiga_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 劇画UIスタイルの見出しフォント（Anton）はGoogle CDNから実行時取得せず、
  // アプリに同梱したファイルのみを使う（プライバシーファースト方針に
  // 合わせ、外部通信を発生させないため）。
  GoogleFonts.config.allowRuntimeFetching = false;
  // 既定のハッシュURL戦略（例: /#/join/xxx）のままだと、招待リンク
  // （例: https://.../join/xxx/yyy、ハッシュ無し）を新しいタブで直接開いた際に
  // go_routerがURLのパス部分をハッシュとして読み取れず、常にルート（語らい
  // タブ）へフォールバックしてしまっていた（招待リンクを踏んでも語らいが
  // 開くだけで何も起きない不具合の原因）。パスベースのURL戦略に切り替える。
  usePathUrlStrategy();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  final initialAccentColor = await loadInitialAccentColor();
  final initialGekigaBackgroundColor = await loadInitialGekigaBackgroundColor();
  final initialAppLocale = await loadInitialAppLocale();
  final initialSendKeyMode = await loadInitialSendKeyMode();
  final initialStickerSendMode = await loadInitialStickerSendMode();
  final initialDraftSyncEnabled = await loadInitialDraftSyncEnabled();
  final initialTerminologyStyle = await loadInitialTerminologyStyle();
  final initialMessageTimeFormat = await loadInitialMessageTimeFormat();
  final initialChatLayoutStyle = await loadInitialChatLayoutStyle();
  final initialAppThemeMode = await loadInitialAppThemeMode();
  final initialAppUiStyle = await loadInitialAppUiStyle();
  runApp(
    ProviderScope(
      overrides: [
        initialAccentColorProvider.overrideWithValue(initialAccentColor),
        initialGekigaBackgroundColorProvider.overrideWithValue(
          initialGekigaBackgroundColor,
        ),
        initialAppLocaleProvider.overrideWithValue(initialAppLocale),
        initialSendKeyModeProvider.overrideWithValue(initialSendKeyMode),
        initialStickerSendModeProvider.overrideWithValue(
          initialStickerSendMode,
        ),
        initialDraftSyncEnabledProvider.overrideWithValue(
          initialDraftSyncEnabled,
        ),
        initialTerminologyStyleProvider.overrideWithValue(
          initialTerminologyStyle,
        ),
        initialMessageTimeFormatProvider.overrideWithValue(
          initialMessageTimeFormat,
        ),
        initialChatLayoutStyleProvider.overrideWithValue(
          initialChatLayoutStyle,
        ),
        initialAppThemeModeProvider.overrideWithValue(initialAppThemeMode),
        initialAppUiStyleProvider.overrideWithValue(initialAppUiStyle),
      ],
      child: const DaiDaiApp(),
    ),
  );
}

class DaiDaiApp extends ConsumerWidget {
  const DaiDaiApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accentColor = ref.watch(accentColorProvider);
    final gekigaBackgroundColor = ref.watch(gekigaBackgroundColorProvider);
    final appLocale = ref.watch(appLocaleProvider);
    final themeMode = ref.watch(appThemeModeProvider);
    final isGekiga = ref.watch(appUiStyleProvider) == AppUiStyle.gekiga;
    // 劇画スタイルはライト/ダークどちらのthemeModeでも同じ見た目にするため、
    // theme/darkThemeの両方に同一のThemeDataを渡す（chat_screen.dartの
    // 既存方針をアプリ全体に拡張したもの）。
    final theme = isGekiga
        ? GekigaTheme.build(gekigaBackgroundColor)
        : AppTheme.light(accentColor);
    final darkTheme = isGekiga
        ? GekigaTheme.build(gekigaBackgroundColor)
        : AppTheme.dark(accentColor);
    return MaterialApp.router(
      title: 'DaiDai',
      debugShowCheckedModeBanner: false,
      theme: theme,
      darkTheme: darkTheme,
      themeMode: themeMode,
      locale: appLocale.locale,
      supportedLocales: AppLocale.values.map((l) => l.locale),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: ref.watch(goRouterProvider),
    );
  }
}
