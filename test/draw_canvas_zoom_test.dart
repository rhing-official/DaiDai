import 'package:daidai/features/note/draw_canvas_view.dart';
import 'package:daidai/l10n/app_locale.dart';
import 'package:daidai/models/app_ui_style.dart';
import 'package:daidai/models/app_user.dart';
import 'package:daidai/models/note_stroke.dart';
import 'package:daidai/providers/app_locale_provider.dart';
import 'package:daidai/providers/app_ui_style_provider.dart';
import 'package:daidai/providers/repository_providers.dart';
import 'package:daidai/repositories/note_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeNotes implements NoteRepository {
  final added = <NoteStroke>[];

  @override
  Stream<List<NoteStroke>> watchStrokes({
    required bool isDm,
    required String conversationId,
    required String roomId,
    required String noteId,
  }) => Stream.value(const []);

  @override
  Future<String> addStroke({
    required bool isDm,
    required String conversationId,
    required String roomId,
    required String noteId,
    required NoteStroke stroke,
  }) async {
    added.add(stroke);
    return 'id${added.length}';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<_FakeNotes> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final notes = _FakeNotes();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        noteRepositoryProvider.overrideWithValue(notes),
        initialAppLocaleProvider.overrideWithValue(AppLocale.japanese),
        initialAppUiStyleProvider.overrideWithValue(AppUiStyle.flat),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: DrawCanvasView(
            isDm: true,
            conversationId: 'dm1',
            roomId: 'room1',
            noteId: 'note1',
            currentUser: AppUser(userId: 'u1', rhingSeed: 'seed'),
            foreground: Colors.black,
            background: Colors.grey.shade200,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return notes;
}

/// キャンバス（白い`Container`）の幅。
double _canvasWidth(WidgetTester tester) {
  final container = tester
      .widgetList<Container>(find.byType(Container))
      .firstWhere((c) => c.color == Colors.white);
  return (container.constraints!).maxWidth;
}

void main() {
  group('純粋関数', () {
    test('clampDrawZoom: 25%〜500%に収める', () {
      expect(clampDrawZoom(0.1), kDrawMinZoom);
      expect(clampDrawZoom(10), kDrawMaxZoom);
      expect(clampDrawZoom(2), 2);
    });

    test('zoomedScrollOffset: 焦点の下のコンテンツが動かない', () {
      // コンテンツ上の点 (offset+focal)/zoom が、倍率変更の前後で同じ位置に残る。
      const offset = 120.0, focal = 80.0, oldZoom = 1.0, newZoom = 2.0;
      final next = zoomedScrollOffset(
        offset: offset,
        focal: focal,
        oldZoom: oldZoom,
        newZoom: newZoom,
      );
      expect((offset + focal) / oldZoom, (next + focal) / newZoom);
    });
  });

  testWidgets('ツールバーの＋／−でキャンバスの幅が変わり、倍率表示をタップで100%へ戻る', (tester) async {
    await _pump(tester);
    expect(_canvasWidth(tester), closeTo(400, 0.01));
    expect(find.text('100%'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.zoom_in));
    await tester.pumpAndSettle();
    expect(_canvasWidth(tester), closeTo(400 * kDrawZoomStep, 0.01));

    await tester.tap(find.byIcon(Icons.zoom_out));
    await tester.tap(find.byIcon(Icons.zoom_out));
    await tester.pumpAndSettle();
    expect(_canvasWidth(tester), closeTo(400 / kDrawZoomStep, 0.01));

    await tester.tap(find.text('${(100 / kDrawZoomStep).round()}%'));
    await tester.pumpAndSettle();
    expect(_canvasWidth(tester), closeTo(400, 0.01));
  });

  testWidgets('拡大してもペンの座標は論理座標（保存値）に正しく変換される', (tester) async {
    final notes = await _pump(tester);
    Finder canvasFinder() => find.byWidgetPredicate(
      (w) => w is Container && w.color == Colors.white,
    );

    // 画面上の点を描き、キャンバス左上からの相対位置と実効倍率から期待値を計算する。
    Future<void> drawAndCheck(double zoom) async {
      final origin = tester.getTopLeft(canvasFinder());
      final start = Offset(origin.dx < 0 ? 40 : origin.dx + 40, origin.dy + 40);
      final gesture = await tester.startGesture(start);
      await gesture.moveBy(const Offset(20, 0));
      await gesture.up();
      await tester.pumpAndSettle();
      final stroke = notes.added.last;
      final scale = 0.4 * zoom; // 400px幅＝論理1000の画面幅フィットに倍率を掛ける
      expect(stroke.points[0], closeTo((start.dx - origin.dx) / scale, 0.2));
      expect(stroke.points[1], closeTo((start.dy - origin.dy) / scale, 0.2));
      expect(stroke.points[2] - stroke.points[0], closeTo(20 / scale, 0.2));
    }

    await drawAndCheck(1.0);
    await tester.tap(find.byIcon(Icons.zoom_in)); // 125%
    await tester.pumpAndSettle();
    await drawAndCheck(kDrawZoomStep);
    await tester.tap(find.byIcon(Icons.zoom_out));
    await tester.tap(find.byIcon(Icons.zoom_out)); // 80%
    await tester.pumpAndSettle();
    await drawAndCheck(1 / kDrawZoomStep);
    expect(notes.added.length, 3);
  });

  testWidgets('2本指のピンチで倍率が変わり、描画中の線は破棄される', (tester) async {
    final notes = await _pump(tester);
    final center = tester.getCenter(find.byType(DrawCanvasView));

    final first = await tester.startGesture(center - const Offset(20, 0));
    await first.moveBy(const Offset(0, 10));
    final second = await tester.startGesture(center + const Offset(20, 0));
    // 2本の距離を広げる（40→120）。
    await first.moveTo(center - const Offset(60, 0));
    await second.moveTo(center + const Offset(60, 0));
    await tester.pump();
    await first.up();
    await second.up();
    await tester.pumpAndSettle();

    expect(notes.added, isEmpty);
    final text = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .firstWhere((t) => t.endsWith('%'));
    expect(int.parse(text.replaceAll('%', '')), greaterThan(150));
  });
}
