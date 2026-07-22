import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/app_gate.dart';
import 'firebase_options.dart';
import 'providers/ui_style_provider.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  final initialUiStyle = await loadInitialUiStyle();
  runApp(
    ProviderScope(
      overrides: [initialUiStyleProvider.overrideWithValue(initialUiStyle)],
      child: const DaiDaiApp(),
    ),
  );
}

class DaiDaiApp extends ConsumerWidget {
  const DaiDaiApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uiStyle = ref.watch(uiStyleProvider);
    return MaterialApp(
      title: 'DaiDai',
      theme: AppTheme.themeFor(uiStyle),
      home: const AppGate(),
    );
  }
}
