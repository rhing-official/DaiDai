import 'package:daidai/models/link_preview.dart';
import 'package:daidai/repositories/link_preview_repository.dart';
import 'package:flutter_test/flutter_test.dart';

class _Inner implements LinkPreviewRepository {
  int calls = 0;
  @override
  Future<LinkPreview?> fetchPreview(String url) async {
    calls++;
    return LinkPreview(url: url, title: 'ogp');
  }
}

/// 招待リンクのチャットのカードは、外部の静止画OGPではなく公開プレビューの
/// アイコン（GIFなら動く元のURL）で組み立てる（2026-11-09）。
void main() {
  test('DaiDaiの招待リンクだけ、種類とidを取り出す', () {
    expect(
      InviteAwareLinkPreviewRepository.parseInvite(
        'https://daidai.rhing.jp/invite/Alice_1',
      ),
      (kind: 'invite', id: 'Alice_1'),
    );
    expect(
      InviteAwareLinkPreviewRepository.parseInvite(
        'https://daidai.rhing.jp/join/g123/abc',
      ),
      (kind: 'join', id: 'g123'),
    );
    expect(
      InviteAwareLinkPreviewRepository.parseInvite(
        'https://example.com/invite/alice',
      ),
      isNull,
    );
    expect(
      InviteAwareLinkPreviewRepository.parseInvite(
        'https://daidai.rhing.jp/settings',
      ),
      isNull,
    );
  });

  test('招待リンクは公開プレビューの元のアイコンURLを画像にし、従来のOGPは呼ばない', () async {
    final inner = _Inner();
    final repo = InviteAwareLinkPreviewRepository(
      inner: inner,
      userPreview: (url, seed) async => LinkPreview(
        url: url,
        title: seed,
        image: 'https://example.com/icon.gif',
      ),
      groupPreview: (url, id) async => null,
    );
    final result = await repo.fetchPreview(
      'https://daidai.rhing.jp/invite/Alice',
    );
    expect(result?.title, 'alice');
    expect(result?.image, 'https://example.com/icon.gif');
    expect(inner.calls, 0);
  });

  test('見つからない・失敗した時、外部のURLは従来のOGPへ戻す', () async {
    final inner = _Inner();
    final repo = InviteAwareLinkPreviewRepository(
      inner: inner,
      userPreview: (url, seed) async => throw StateError('x'),
      groupPreview: (url, id) async => null,
    );
    expect(
      (await repo.fetchPreview('https://daidai.rhing.jp/invite/a'))?.title,
      'ogp',
    );
    expect(
      (await repo.fetchPreview('https://daidai.rhing.jp/join/g'))?.title,
      'ogp',
    );
    expect((await repo.fetchPreview('https://example.com/x'))?.title, 'ogp');
    expect(inner.calls, 3);
  });
}
