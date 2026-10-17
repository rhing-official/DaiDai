import 'package:daidai/features/guide/first_guide_screen.dart';
import 'package:daidai/l10n/app_locale.dart';
import 'package:daidai/l10n/guide_content.dart';
import 'package:daidai/models/app_user_preferences.dart';
import 'package:daidai/providers/app_locale_provider.dart';
import 'package:daidai/providers/repository_providers.dart';
import 'package:daidai/repositories/user_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeUserRepository implements UserRepository {
  final writes = <(String, String, Object?)>[];
  bool failWrite = false;

  @override
  Future<void> updateUserPreference(
    String userId,
    String field,
    Object? value,
  ) async {
    if (failWrite) throw StateError('offline');
    writes.add((userId, field, value));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<_FakeUserRepository> _pump(
  WidgetTester tester, {
  required VoidCallback onCompleted,
  String? userId = 'u1',
  bool failWrite = false,
}) async {
  tester.view.physicalSize = const Size(800, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final repo = _FakeUserRepository()..failWrite = failWrite;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        initialAppLocaleProvider.overrideWithValue(AppLocale.japanese),
        userRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp(
        home: FirstGuideScreen(userId: userId, onCompleted: onCompleted),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return repo;
}

void main() {
  group('ガイドの内容', () {
    test('機能別ガイドのidに重複が無く、日英とも本文が空でない', () {
      final ids = guideTopics.map((t) => t.id).toList();
      expect(ids.toSet().length, ids.length);
      for (final topic in guideTopics) {
        expect(topic.steps, isNotEmpty, reason: topic.id);
        for (final text in [topic.title, topic.summary, ...topic.steps]) {
          expect(text.ja.trim(), isNotEmpty, reason: topic.id);
          expect(text.en.trim(), isNotEmpty, reason: topic.id);
        }
      }
    });

    test('初回ガイドは4枚で、日英とも空でない', () {
      expect(firstGuidePages, hasLength(4));
      for (final page in firstGuidePages) {
        for (final text in [page.title, page.body]) {
          expect(text.ja.trim(), isNotEmpty);
          expect(text.en.trim(), isNotEmpty);
        }
      }
    });
  });

  group('guideSeen', () {
    test('未設定（既存住人）はnullで、JSONにも出ない', () {
      final prefs = AppUserPreferences.fromJson(const {});
      expect(prefs.guideSeen, isNull);
      expect(prefs.toJson().containsKey('guideSeen'), isFalse);
    });

    test('false（新規で未視聴）とtrue（視聴済み）がJSONで往復する', () {
      for (final value in [false, true]) {
        final prefs = AppUserPreferences(guideSeen: value);
        expect(prefs.toJson()['guideSeen'], value);
        expect(AppUserPreferences.fromJson(prefs.toJson()).guideSeen, value);
      }
    });
  });

  group('FirstGuideScreen', () {
    testWidgets('最後まで進むと視聴済みを記録して完了を1回だけ通知する', (tester) async {
      var completed = 0;
      final repo = await _pump(tester, onCompleted: () => completed++);

      expect(find.text('DaiDaiへようこそ'), findsOneWidget);
      for (var i = 0; i < firstGuidePages.length - 1; i++) {
        await tester.tap(find.text('次へ'));
        await tester.pumpAndSettle();
      }
      expect(find.text('はじめる'), findsOneWidget);
      await tester.tap(find.text('はじめる'));
      await tester.pumpAndSettle();

      expect(completed, 1);
      expect(repo.writes, [('u1', 'guideSeen', true)]);
    });

    testWidgets('スキップでも視聴済みを記録して完了を通知する', (tester) async {
      var completed = 0;
      final repo = await _pump(tester, onCompleted: () => completed++);
      await tester.tap(find.text('スキップ'));
      await tester.pumpAndSettle();
      expect(completed, 1);
      expect(repo.writes, [('u1', 'guideSeen', true)]);
    });

    testWidgets('スワイプでも次の枚へ進める', (tester) async {
      await _pump(tester, onCompleted: () {});
      await tester.drag(find.byType(PageView), const Offset(-500, 0));
      await tester.pumpAndSettle();
      expect(find.text('語らいで話す'), findsOneWidget);
    });

    testWidgets('設定からの再表示（userIdなし）では記録を更新しない', (tester) async {
      var completed = 0;
      final repo = await _pump(
        tester,
        userId: null,
        onCompleted: () => completed++,
      );
      await tester.tap(find.text('スキップ'));
      await tester.pumpAndSettle();
      expect(completed, 1);
      expect(repo.writes, isEmpty);
    });

    testWidgets('記録の書き込みに失敗しても先へ進める', (tester) async {
      var completed = 0;
      await _pump(tester, failWrite: true, onCompleted: () => completed++);
      await tester.tap(find.text('スキップ'));
      await tester.pumpAndSettle();
      expect(completed, 1);
    });
  });
}
