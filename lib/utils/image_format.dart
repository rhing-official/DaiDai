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
