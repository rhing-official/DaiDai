/// 取り込む曲の入力元（ファイル選択・ディレクトリ選択）。Webだけで使う（2026-11-15）。
library;

import 'dart:typed_data';

export 'bgm_import_source_stub.dart'
    if (dart.library.js_interop) 'bgm_import_source_web.dart';

/// 選んだファイル1つ。中身は[readBytes]で、必要になった時に読む（ディレクトリごと選んでも、
/// 全部をいちどにメモリへ載せない）。
class BgmImportFile {
  const BgmImportFile({
    required this.name,
    this.folderPath = const [],
    required this.readBytes,
  });

  /// ファイル名（拡張子付き）。
  final String name;

  /// 選んだディレクトリからの、親ディレクトリ名の並び（外側→内側。ファイルを個別に選んだ時は空）。
  final List<String> folderPath;

  /// 一番近い親ディレクトリ名（無ければnull）。
  String? get folder => folderPath.isEmpty ? null : folderPath.last;

  final Future<Uint8List> Function() readBytes;
}

const bgmAudioExtensions = {
  'mp3',
  'm4a',
  'mp4',
  'aac',
  'wav',
  'ogg',
  'oga',
  'opus',
  'flac',
  'webm',
};

bool isBgmAudioFileName(String name) {
  final dot = name.lastIndexOf('.');
  if (dot < 0) return false;
  return bgmAudioExtensions.contains(name.substring(dot + 1).toLowerCase());
}

// 「ディスク」と全角コロンは、日本語の文字を直書きしない為、コードポイントで書く。
final _discDir = RegExp(
  r'^\s*(?:dis[ck]|cd|\u30C7\u30A3\u30B9\u30AF)\s*[-_.]?\s*(\d{1,2})(?:\s|$|[-_.:\uFF1A])',
  caseSensitive: false,
);

/// `Disc 2`・`disc2`・`CD2`・`ディスク2`のようなディレクトリ名のディスク番号（それ以外はnull）。
int? parseDiscFromDirName(String name) {
  final m = _discDir.firstMatch(name);
  if (m == null) return null;
  final n = int.tryParse(m.group(1)!);
  return (n == null || n <= 0) ? null : n;
}

/// タグにアルバム名が無い曲のアルバム名。パスの内側から外側へ見て、ディスクを表さない最初の
/// ディレクトリ名（`ALBUM/CD1`なら`ALBUM`）。無ければnull。
String? albumNameFromPath(List<String> folderPath) {
  for (final dir in folderPath.reversed) {
    if (dir.trim().isEmpty) continue;
    if (parseDiscFromDirName(dir) == null) return dir.trim();
  }
  return null;
}

/// パスに含まれるディスク番号（一番内側のもの）。無ければnull。
int? discFromPath(List<String> folderPath) {
  for (final dir in folderPath.reversed) {
    final n = parseDiscFromDirName(dir);
    if (n != null) return n;
  }
  return null;
}
