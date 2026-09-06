import 'dart:typed_data';

/// 着信音・呼出音のカスタムアップロードの容量上限。数秒〜十数秒程度の
/// 短い音源を想定した現実的な上限（Telegramの300KB/5秒・Discordの
/// チャンネル音512KBより緩め）。長さそのものの厳密なバリデーションは
/// v1では行わない。
const int kMaxSoundUploadSizeBytes = 2 * 1024 * 1024;

const Set<String> kAllowedSoundExtensions = {'mp3', 'wav', 'm4a', 'ogg'};

/// [kMaxSoundUploadSizeBytes]超過。呼び出し元のUIがエラーメッセージを
/// 出し分けるための専用型（`attachment_upload.dart`の
/// `AttachmentTooLargeException`と同じ考え方）。
class SoundUploadTooLargeException implements Exception {
  const SoundUploadTooLargeException();
}

/// [kAllowedSoundExtensions]に含まれない拡張子。
class SoundUploadUnsupportedFormatException implements Exception {
  const SoundUploadUnsupportedFormatException();
}

/// アップロードしようとしている音声ファイルを検証する。問題が無ければ
/// 何も返さず、問題があれば対応する例外を投げる。
void validateSoundUpload(Uint8List bytes, String fileName) {
  if (bytes.lengthInBytes > kMaxSoundUploadSizeBytes) {
    throw const SoundUploadTooLargeException();
  }
  if (!kAllowedSoundExtensions.contains(soundExtensionOf(fileName))) {
    throw const SoundUploadUnsupportedFormatException();
  }
}

String soundExtensionOf(String fileName) {
  final dotIndex = fileName.lastIndexOf('.');
  if (dotIndex == -1 || dotIndex == fileName.length - 1) return '';
  return fileName.substring(dotIndex + 1).toLowerCase();
}

String soundMimeTypeFor(String extension) => switch (extension) {
  'mp3' => 'audio/mpeg',
  'wav' => 'audio/wav',
  'm4a' => 'audio/mp4',
  'ogg' => 'audio/ogg',
  _ => 'application/octet-stream',
};
