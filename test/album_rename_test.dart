import 'package:daidai/features/album/album_pane_view.dart';
import 'package:daidai/l10n/app_locale.dart';
import 'package:daidai/models/album.dart';
import 'package:daidai/models/album_item.dart';
import 'package:daidai/models/app_ui_style.dart';
import 'package:daidai/providers/app_locale_provider.dart';
import 'package:daidai/providers/app_ui_style_provider.dart';
import 'package:daidai/providers/repository_providers.dart';
import 'package:daidai/repositories/album_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAlbumRepository implements AlbumRepository {
  final List<String> renamed = [];

  @override
  Stream<List<AlbumItem>> watchItems({
    required bool isDm,
    required String conversationId,
    required String roomId,
    required String albumId,
  }) => Stream.value(const []);

  @override
  Future<void> renameAlbum({
    required bool isDm,
    required String conversationId,
    required String roomId,
    required String albumId,
    required String name,
  }) async {
    renamed.add(name);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<_FakeAlbumRepository> _open(WidgetTester tester, {Size? size}) async {
  if (size != null) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }
  final repo = _FakeAlbumRepository();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        initialAppLocaleProvider.overrideWithValue(AppLocale.japanese),
        initialAppUiStyleProvider.overrideWithValue(AppUiStyle.flat),
        albumRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp(
        home: AlbumPaneView(
          isDm: true,
          conversationId: 'c',
          roomId: 'r',
          album: const Album(
            albumId: 'a',
            roomId: 'r',
            name: '旅行',
            createdBy: 'u',
          ),
          currentUserId: 'u',
          onClose: () {},
        ),
      ),
    ),
  );
  await tester.pump();
  return repo;
}

void main() {
  testWidgets('暗幕などで閉じられても、変えた名前が保存される', (tester) async {
    final repo = await _open(tester);
    await tester.enterText(find.byType(TextField), '温泉旅行');
    await tester.pumpWidget(const SizedBox());
    expect(repo.renamed, ['温泉旅行']);
  });

  testWidgets('空欄で閉じた時は保存せず、元の名前のまま', (tester) async {
    final repo = await _open(tester);
    await tester.enterText(find.byType(TextField), '   ');
    await tester.pumpWidget(const SizedBox());
    expect(repo.renamed, isEmpty);
  });

  testWidgets('変えていなければ保存しない', (tester) async {
    final repo = await _open(tester);
    await tester.pumpWidget(const SizedBox());
    expect(repo.renamed, isEmpty);
  });

  testWidgets('狭い幅（縦画面）では、ボタンの行と題名の行が分かれ、広い幅では同じ行', (tester) async {
    await _open(tester, size: const Size(330, 700));
    final narrowTitle = tester.getTopLeft(find.byType(TextField)).dy;
    final narrowButton = tester
        .getTopLeft(find.byIcon(Icons.delete_outline))
        .dy;
    expect(narrowTitle, greaterThan(narrowButton + 20));

    await _open(tester, size: const Size(900, 700));
    await tester.pumpAndSettle();
    final wideTitle = tester.getCenter(find.byType(TextField)).dy;
    final wideButton = tester.getCenter(find.byIcon(Icons.delete_outline)).dy;
    expect((wideTitle - wideButton).abs(), lessThan(10));
  });
}
