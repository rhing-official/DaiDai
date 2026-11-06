import 'package:flutter/foundation.dart';

/// 通話の診断ログ（2026-11-03）。映像が届かない・接続が遅い、といった不具合を実機で
/// 切り分ける為、ブラウザのコンソール（F12）で`[CALL]`を検索して見る。
void callLog(String message) => debugPrint('[CALL] $message');
