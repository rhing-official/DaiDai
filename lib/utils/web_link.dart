import 'package:flutter/foundation.dart' show kIsWeb;

/// Web版が動いている本番ドメイン。ネイティブ版（デスクトップ・モバイル）では
/// `Uri.base`が実際のWebホストを指さないため、外部から開けるリンクとして
/// 常にこちらを使う。Web版はビルド元のオリジン（開発サーバーのポート含む）を
/// そのまま使う。
const kProductionWebOrigin = 'https://dai-dai-phi.vercel.app';

/// アプリ内の`path`（例: `/invite/xxx`）から、外部で開ける絶対URLを組み立てる。
String buildWebLink(String path) {
  final origin = kIsWeb ? Uri.base.origin : kProductionWebOrigin;
  return '$origin$path';
}
