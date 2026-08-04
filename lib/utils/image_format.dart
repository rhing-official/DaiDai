import 'dart:typed_data';

/// GIFのマジックバイト（`GIF87a`/`GIF89a`）を先頭から判定する。
///
/// `flutter_image_compress`はGIFを渡しても最初の1フレームだけを
/// デコードして静止画のWebPにしてしまい、アニメーションが失われる。
/// アイコン・背景画像のアップロード時にGIFだけは圧縮をスキップして
/// 元のバイトのままアップロードするための判定に使う。
bool isGifBytes(Uint8List bytes) {
  if (bytes.length < 6) return false;
  const header = [0x47, 0x49, 0x46, 0x38]; // "GIF8"
  for (var i = 0; i < header.length; i++) {
    if (bytes[i] != header[i]) return false;
  }
  return bytes[4] == 0x37 || bytes[4] == 0x39; // '7' (87a) or '9' (89a)
}

bool _isPngBytes(Uint8List bytes) {
  const header = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  if (bytes.length < header.length) return false;
  for (var i = 0; i < header.length; i++) {
    if (bytes[i] != header[i]) return false;
  }
  return true;
}

/// アイコン・背景画像アップロード時、WebP圧縮を行わず元のバイトのまま
/// アップロードする場合（Windows/Linux、または圧縮失敗時）に使う、実際の
/// 拡張子とContent-Typeの組。マジックバイトから判定できない形式は
/// （従来の挙動を維持するため）JPEGとして扱う。
///
/// 圧縮をスキップしたPNG（透過を持つ場合がある）に対して、従来はここを
/// 一律`.jpg`/`image/jpeg`と誤表記していた。PNGはアルファチャンネルを
/// 持つがJPEGは持たないため、この誤表記自体が透過を壊すわけではないが、
/// 実際のバイト列と食い違うContent-Typeはブラウザ等のMIMEスニッフィングで
/// 正しく表示されない要因になりうるため、実際の形式に合わせる
/// （2026-08-04追加）。
({String extension, String contentType}) rawUploadFormatFor(Uint8List bytes) {
  if (_isPngBytes(bytes)) return (extension: 'png', contentType: 'image/png');
  return (extension: 'jpg', contentType: 'image/jpeg');
}
