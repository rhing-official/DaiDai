import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

/// モバイル（Android/iOS）実機かどうか。Web版は常にfalse
/// （`kIsWeb`が先に評価されるため`Platform`自体には触れない）。通話UIの
/// 全画面/PC埋め込み表示の出し分け（2026-08-19追加）等、画面幅ではなく
/// 実際のプラットフォームで判定したい場面に使う。
bool get isMobileCallPlatform =>
    !kIsWeb && (Platform.isAndroid || Platform.isIOS);
