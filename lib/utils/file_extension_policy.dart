/// ファイル送信の容量上限（技術仕様書5.2参照）。超過分はSudachi（P2P、
/// 未実装）へ誘導する想定のため、現時点ではこの上限を超えるファイルは
/// 送信そのものを拒否する。
const int kMaxAttachmentSizeBytes = 2 * 1024 * 1024 * 1024;

/// ファイル送信で拒否する拡張子（実行ファイル・スクリプト系のみ、
/// 技術仕様書5.2のブロックリスト方式）。画像・動画は形式チェックのみで
/// この一覧の対象外（`sendAttachmentMessage`参照）。小文字・ドット無しで
/// 保持する。
const Set<String> kBlockedFileExtensions = {
  'exe',
  'msi',
  'bat',
  'cmd',
  'com',
  'scr',
  'ps1',
  'vbs',
  'jar',
  'apk',
  'app',
  'dmg',
  'sh',
};

/// [fileName]の拡張子が[kBlockedFileExtensions]に含まれるかどうか。
/// 拡張子が無いファイルはブロックしない。
bool isBlockedFileExtension(String fileName) {
  final dotIndex = fileName.lastIndexOf('.');
  if (dotIndex == -1 || dotIndex == fileName.length - 1) return false;
  final extension = fileName.substring(dotIndex + 1).toLowerCase();
  return kBlockedFileExtensions.contains(extension);
}
