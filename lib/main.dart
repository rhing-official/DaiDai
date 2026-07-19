import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/app_gate.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const ProviderScope(child: DaiDaiApp()));
}

class DaiDaiApp extends StatelessWidget {
  const DaiDaiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DaiDai',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFEE7800)),
        useMaterial3: true,
      ),
      home: const AppGate(),
    );
  }
}
