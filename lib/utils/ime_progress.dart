import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// ソフトキーボードの開閉の途中の高さ（2026-11-21）。Androidだけ、OSのキーボードの
/// 動き（`WindowInsetsAnimation`）を毎フレーム受け取る。
///
/// FlutterのviewInsetsは、Android 16の端末で動きが終わった後に1回だけ最終値で届き、
/// それを基準にすると、メッセージ一覧・入力欄がキーボードより遅れて動いていた。
/// 動いている間は[live]に途中の高さ（dp）が入り、動きが終わると少し待ってnullに戻る
/// （その頃にはviewInsetsも最終値に追い付いている）。受け取れない端末・OS・Webでは
/// 常にnullのまま（呼び出し側が従来の補間にフォールバックする）。
class ImeProgress {
  ImeProgress._();

  static final ValueNotifier<double?> live = ValueNotifier<double?>(null);

  static const _channel = MethodChannel('jp.rhing.daidai/ime');
  static bool _initialized = false;
  static Timer? _releaseTimer;

  static bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// 最初の1回だけ呼べば、以降は受信が続く。
  static void ensureInitialized() {
    if (_initialized || !_supported) return;
    _initialized = true;
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'progress':
          _releaseTimer?.cancel();
          live.value = (call.arguments as num).toDouble();
        case 'end':
          // viewInsetsが最終値に追い付くまでの間、最後の値を保つ。
          _releaseTimer?.cancel();
          _releaseTimer = Timer(
            const Duration(milliseconds: 300),
            () => live.value = null,
          );
      }
    });
  }
}
