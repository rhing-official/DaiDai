import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

bool get isPortraitScreen => web.window.innerHeight > web.window.innerWidth;

/// 向きの変化（`screen.orientation`の`change`、古いブラウザ向けに
/// `orientationchange`）を流す。購読を止めるとリスナーも外す。
Stream<void> screenOrientationChanges() {
  late final StreamController<void> controller;
  final listener = ((web.Event _) {
    if (!controller.isClosed) controller.add(null);
  }).toJS;
  controller = StreamController<void>(
    onListen: () {
      web.window.addEventListener('orientationchange', listener);
      web.window.screen.orientation.addEventListener('change', listener);
    },
    onCancel: () {
      web.window.removeEventListener('orientationchange', listener);
      web.window.screen.orientation.removeEventListener('change', listener);
    },
  );
  return controller.stream;
}
