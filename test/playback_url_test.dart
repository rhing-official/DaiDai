import 'package:daidai/models/message.dart';
import 'package:daidai/widgets/media_viewer_screen.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _json({Map<String, dynamic> extra = const {}}) => {
  'url': 'https://example.com/original.mp4',
  'fileName': 'original.mp4',
  'extension': 'mp4',
  'sizeBytes': 1,
  'mimeType': 'video/mp4',
  ...extra,
};

void main() {
  test('再生用の軽い版（サーバーが書く）を読み込める', () {
    final meta = MessageFileMetadata.fromJson(
      _json(
        extra: {
          'playbackPath': 'dmFiles/dm1/m1_play.mp4',
          'playbackUrl': 'https://example.com/play.mp4',
        },
      ),
    );
    expect(meta.playbackPath, 'dmFiles/dm1/m1_play.mp4');
    expect(meta.playbackUrl, 'https://example.com/play.mp4');
    expect(meta.url, 'https://example.com/original.mp4');
  });

  test('軽い版が無い動画はnullのままで、書き出しにも含めない（サーバーの値を消さない）', () {
    final meta = MessageFileMetadata.fromJson(_json());
    expect(meta.playbackUrl, isNull);
    expect(meta.toJson().containsKey('playbackUrl'), isFalse);
    expect(meta.toJson().containsKey('playbackPath'), isFalse);
  });

  test('サーバーが書いた軽い版は、書き出しでも保たれる', () {
    final meta = MessageFileMetadata.fromJson(
      _json(extra: {'playbackPath': 'p', 'playbackUrl': 'u'}),
    );
    expect(meta.toJson()['playbackPath'], 'p');
    expect(meta.toJson()['playbackUrl'], 'u');
  });

  test('ビューアの項目は、再生用のURLを持てて、元のURLはそのまま', () {
    const item = MediaViewerItem(
      id: 'a',
      url: 'https://example.com/original.mp4',
      contentType: 'video',
      playbackUrl: 'https://example.com/play.mp4',
    );
    expect(item.url, 'https://example.com/original.mp4');
    expect(item.playbackUrl, 'https://example.com/play.mp4');
  });
}
