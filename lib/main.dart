import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'firebase_options.dart';
import 'l10n/app_locale.dart';
import 'providers/accent_color_provider.dart';
import 'providers/app_locale_provider.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  final initialAccentColor = await loadInitialAccentColor();
  final initialAppLocale = await loadInitialAppLocale();
  runApp(
    ProviderScope(
      overrides: [
        initialAccentColorProvider.overrideWithValue(initialAccentColor),
        initialAppLocaleProvider.overrideWithValue(initialAppLocale),
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
    return MaterialApp.router(
      title: 'DaiDai',
      theme: AppTheme.theme(accentColor),
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
