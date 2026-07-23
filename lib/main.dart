import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'firebase_options.dart';
import 'providers/accent_color_provider.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  final initialAccentColor = await loadInitialAccentColor();
  runApp(
    ProviderScope(
      overrides: [
        initialAccentColorProvider.overrideWithValue(initialAccentColor),
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
    return MaterialApp.router(
      title: 'DaiDai',
      theme: AppTheme.theme(accentColor),
      routerConfig: ref.watch(goRouterProvider),
    );
  }
}
