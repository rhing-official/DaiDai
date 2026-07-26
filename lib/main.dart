import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import 'firebase_options.dart';
import 'l10n/app_locale.dart';
import 'providers/accent_color_provider.dart';
import 'providers/app_locale_provider.dart';
import 'providers/chat_layout_style_provider.dart';
import 'providers/message_time_format_provider.dart';
import 'providers/send_key_mode_provider.dart';
import 'providers/terminology_style_provider.dart';
import 'providers/theme_mode_provider.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 既定のハッシュURL戦略（例: /#/join/xxx）のままだと、招待リンク
  // （例: https://.../join/xxx/yyy、ハッシュ無し）を新しいタブで直接開いた際に
  // go_routerがURLのパス部分をハッシュとして読み取れず、常にルート（語らい
  // タブ）へフォールバックしてしまっていた（招待リンクを踏んでも語らいが
  // 開くだけで何も起きない不具合の原因）。パスベースのURL戦略に切り替える。
  usePathUrlStrategy();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  final initialAccentColor = await loadInitialAccentColor();
  final initialAppLocale = await loadInitialAppLocale();
  final initialSendKeyMode = await loadInitialSendKeyMode();
  final initialTerminologyStyle = await loadInitialTerminologyStyle();
  final initialMessageTimeFormat = await loadInitialMessageTimeFormat();
  final initialChatLayoutStyle = await loadInitialChatLayoutStyle();
  final initialAppThemeMode = await loadInitialAppThemeMode();
  runApp(
    ProviderScope(
      overrides: [
        initialAccentColorProvider.overrideWithValue(initialAccentColor),
        initialAppLocaleProvider.overrideWithValue(initialAppLocale),
        initialSendKeyModeProvider.overrideWithValue(initialSendKeyMode),
        initialTerminologyStyleProvider.overrideWithValue(
          initialTerminologyStyle,
        ),
        initialMessageTimeFormatProvider.overrideWithValue(
          initialMessageTimeFormat,
        ),
        initialChatLayoutStyleProvider.overrideWithValue(initialChatLayoutStyle),
        initialAppThemeModeProvider.overrideWithValue(initialAppThemeMode),
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
    final appLocale = ref.watch(appLocaleProvider);
    final themeMode = ref.watch(appThemeModeProvider);
    return MaterialApp.router(
      title: 'DaiDai',
      theme: AppTheme.light(accentColor),
      darkTheme: AppTheme.dark(accentColor),
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
