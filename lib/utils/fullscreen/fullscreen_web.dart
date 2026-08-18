import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// ブラウザ本来のFullscreen API（[fullscreen.dart]参照、2026-08-18追加）。
/// タブ・アドレスバー等のブラウザUIごと隠す本来の全画面表示を行う。
/// ユーザー操作（キー入力）起点で呼ばれない場合、ブラウザ側の制約で
/// 拒否されることがあるため、失敗は無視する。
bool get isDocumentFullscreen => web.document.fullscreenElement != null;

Future<void> requestDocumentFullscreen() async {
  final element = web.document.documentElement;
  if (element == null) return;
  try {
    await element.requestFullscreen().toDart;
  } catch (_) {}
}

Future<void> exitDocumentFullscreen() async {
  if (!isDocumentFullscreen) return;
  try {
    await web.document.exitFullscreen().toDart;
  } catch (_) {}
}
