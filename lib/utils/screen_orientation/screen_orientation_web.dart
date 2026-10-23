import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

bool get isPortraitScreen => web.window.innerHeight > web.window.innerWidth;

/// 向きの変化（`screen.orientation`の`change`、古いブラウザ向けに
/// `orientationchange`、それらが来ないブラウザ向けに`resize`で縦横が反転した時）
/// を流す。購読を止めるとリスナーも外す。
Stream<void> screenOrientationChanges() {
  late final StreamController<void> controller;
  var portrait = isPortraitScreen;
  final listener = ((web.Event _) {
    portrait = isPortraitScreen;
    if (!controller.isClosed) controller.add(null);
  }).toJS;
  final resizeListener = ((web.Event _) {
    final now = isPortraitScreen;
    if (now == portrait) return;
    portrait = now;
    if (!controller.isClosed) controller.add(null);
  }).toJS;
  controller = StreamController<void>(
    onListen: () {
      web.window.addEventListener('orientationchange', listener);
      web.window.screen.orientation.addEventListener('change', listener);
      web.window.addEventListener('resize', resizeListener);
    },
    onCancel: () {
      web.window.removeEventListener('orientationchange', listener);
      web.window.screen.orientation.removeEventListener('change', listener);
      web.window.removeEventListener('resize', resizeListener);
    },
  );
  return controller.stream;
}
