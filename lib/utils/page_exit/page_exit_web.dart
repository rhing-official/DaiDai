import 'dart:js_interop';

import 'package:web/web.dart' as web;

void Function() onPageExit(void Function() callback) {
  final listener = ((web.Event _) => callback()).toJS;
  web.window.addEventListener('pagehide', listener);
  return () => web.window.removeEventListener('pagehide', listener);
}
