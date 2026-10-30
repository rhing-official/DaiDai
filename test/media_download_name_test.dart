import 'package:daidai/widgets/media_viewer_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  MediaViewerItem item(String url, {String? fileName, String type = 'image'}) =>
      MediaViewerItem(id: 'a', url: url, contentType: type, fileName: fileName);

  test('ファイル名があればそれを使う', () {
    expect(
      mediaDownloadFileName(item('https://x/y.png', fileName: 'photo.png')),
      'photo.png',
    );
  });

  test('無ければURLの末尾（Storageの%2F区切りも復号）から取る', () {
    expect(
      mediaDownloadFileName(item('https://x/a/b/c.png?alt=media')),
      'c.png',
    );
    expect(
      mediaDownloadFileName(
        item(
          'https://firebasestorage.googleapis.com/v0/b/x/o/dm%2F1%2Fcat.jpg?alt=media',
        ),
      ),
      'cat.jpg',
    );
  });

  test('取れなければ種類ごとの既定名', () {
    expect(mediaDownloadFileName(item('')), 'image');
    expect(mediaDownloadFileName(item('', type: 'video')), 'video');
  });
}
