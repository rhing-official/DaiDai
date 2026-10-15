import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

Completer<String?>? _pending;
bool _installed = false;

void _install() {
  if (_installed) return;
  _installed = true;
  // キャプチャ段階でdocumentから受ける（フォーカス要素に依らず拾うため）。
  web.document.addEventListener(
    'paste',
    ((web.Event event) {
      final pending = _pending;
      if (pending == null || pending.isCompleted) return;
      final text = (event as web.ClipboardEvent).clipboardData?.getData(
        'text/plain',
      );
      // ブラウザ既定の貼り付け（隠しinputへの挿入）は止め、こちらで貼る。
      // 止めないと、エディタの入力経路でも同じ文字が挿入されて二重になる。
      event.preventDefault();
      pending.complete(text);
    }).toJS,
    web.AddEventListenerOptions(capture: true),
  );
}

Future<String?> readPasteEventText({
  Duration timeout = const Duration(milliseconds: 800),
}) {
  _install();
  final completer = Completer<String?>();
  _pending = completer;
  return completer.future.timeout(timeout, onTimeout: () => null);
}
