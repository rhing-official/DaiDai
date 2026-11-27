import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'pasted_file.dart';

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

/// クリップボードにファイルが有る貼り付けを受け取る。テキストだけの貼り付けには
/// 触れない（入力欄の通常の貼り付けのまま）。ファイルを受けた時だけ、ブラウザ既定の
/// 挿入を止める。
void Function() listenPasteFiles(
  void Function(List<PastedFile> files) onFiles,
) {
  final listener = ((web.Event event) {
    final files = (event as web.ClipboardEvent).clipboardData?.files;
    if (files == null || files.length == 0) return;
    event.preventDefault();
    final picked = [for (var i = 0; i < files.length; i++) files.item(i)!];
    () async {
      final result = <PastedFile>[];
      for (final f in picked) {
        final buffer = await f.arrayBuffer().toDart;
        result.add(
          PastedFile(
            bytes: buffer.toDart.asUint8List(),
            name: f.name,
            mimeType: f.type,
          ),
        );
      }
      onFiles(result);
    }();
  }).toJS;
  final options = web.AddEventListenerOptions(capture: true);
  web.document.addEventListener('paste', listener, options);
  return () => web.document.removeEventListener(
    'paste',
    listener,
    web.EventListenerOptions(capture: true),
  );
}
