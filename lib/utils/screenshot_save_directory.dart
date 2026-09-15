import 'dart:io';

/// コンピューター版（Windows/Linux/macOS）で、チャットのスクリーンショット
/// 機能がPNGを保存する先のディレクトリ（無ければ作成して返す）
/// （2026-09-15追加、[isDesktopPlatform]参照）。`path_provider`はDownloads
/// フォルダ相当までしか標準化しておらず「スクリーンショット」専用
/// ディレクトリという概念自体を持たないため、各OSの実際のスクリーンショット
/// ツールの既定保存先の慣習に合わせてパスを組み立てる:
///
/// - Windows: `%USERPROFILE%\Pictures\Screenshots`（Win+PrtScn等の既定
///   保存先と同じ慣習）。
/// - macOS: `defaults read com.apple.screencapture location`
///   （`screencapture`コマンドの保存先設定）で確認できるユーザー設定。
///   未設定・コマンド失敗時はmacOSの既定である`~/Desktop`。
/// - Linux: `~/Pictures/Screenshots`（GNOME等で広く使われる慣習。
///   デスクトップ環境によって異なり得るが、`path_provider`/XDGにも
///   「スクリーンショット」専用ディレクトリの概念自体が無いため、最も
///   一般的な慣習を採用する）。
Future<Directory> resolveScreenshotSaveDirectory() async {
  final Directory directory;
  if (Platform.isWindows) {
    final home =
        Platform.environment['USERPROFILE'] ?? Directory.systemTemp.path;
    directory = Directory('$home\\Pictures\\Screenshots');
  } else if (Platform.isMacOS) {
    final home = Platform.environment['HOME'] ?? Directory.systemTemp.path;
    String? customLocation;
    try {
      final result = await Process.run('defaults', [
        'read',
        'com.apple.screencapture',
        'location',
      ]);
      if (result.exitCode == 0) {
        final output = (result.stdout as String).trim();
        if (output.isNotEmpty) customLocation = output;
      }
    } catch (_) {
      // コマンド自体が使えない/未設定の場合は既定のデスクトップへ
      // フォールバックする。
    }
    directory = Directory(customLocation ?? '$home/Desktop');
  } else {
    // Linux
    final home = Platform.environment['HOME'] ?? Directory.systemTemp.path;
    directory = Directory('$home/Pictures/Screenshots');
  }
  if (!await directory.exists()) {
    await directory.create(recursive: true);
  }
  return directory;
}
