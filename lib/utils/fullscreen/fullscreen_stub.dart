/// Web以外のプラットフォーム向けの何もしない実装（[fullscreen.dart]参照）。
bool get isDocumentFullscreen => false;

Future<void> requestDocumentFullscreen() async {}

Future<void> exitDocumentFullscreen() async {}
