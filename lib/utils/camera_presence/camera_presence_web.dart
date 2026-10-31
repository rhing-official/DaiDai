import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// ブラウザのデバイス一覧に映像入力があるか。許可は求めない（許可前はラベル・
/// IDが空でも、種別は一覧に出る）。取得できない場合はnull（不明）。
Future<bool?> webHasCamera() async {
  try {
    final devices =
        (await web.window.navigator.mediaDevices.enumerateDevices().toDart)
            .toDart;
    return devices.any((d) => d.kind == 'videoinput');
  } catch (_) {
    return null;
  }
}
