import 'package:daidai/features/auth/residence_survey_screen.dart';
import 'package:daidai/l10n/app_locale.dart';
import 'package:daidai/l10n/country_data.dart';
import 'package:daidai/l10n/prefecture_data.dart';
import 'package:daidai/models/residence.dart';
import 'package:daidai/providers/app_locale_provider.dart';
import 'package:daidai/providers/repository_providers.dart';
import 'package:daidai/repositories/residence_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeResidenceRepository implements ResidenceRepository {
  final saved = <String, Residence>{};

  @override
  Future<Residence?> getResidence(String userId) async => saved[userId];

  @override
  Future<void> saveResidence(String userId, Residence residence) async {
    saved[userId] = residence;
  }
}

Future<_FakeResidenceRepository> _pump(
  WidgetTester tester, {
  required VoidCallback onCompleted,
  Residence? initial,
}) async {
  tester.view.physicalSize = const Size(800, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final repo = _FakeResidenceRepository();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        initialAppLocaleProvider.overrideWithValue(AppLocale.japanese),
        residenceRepositoryProvider.overrideWithValue(repo),
        // 言語の切り替えが、ログイン中ならFirestoreへも書くために参照する。
        authStateProvider.overrideWith((ref) => Stream.value(null)),
      ],
      child: MaterialApp(
        locale: const Locale('ja'),
        supportedLocales: const [Locale('ja'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: ResidenceSurveyScreen(
          userId: 'u1',
          onCompleted: onCompleted,
          initial: initial,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return repo;
}

Future<void> _selectCountry(WidgetTester tester, String name) async {
  await tester.tap(find.text('国を選ぶ'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(name));
  await tester.pumpAndSettle();
}

void main() {
  group('国・都道府県データ', () {
    test('国コードに重複が無く、時差が複数ある国の候補に既定が含まれる', () {
      final codes = countries.map((c) => c.code).toList();
      expect(codes.toSet().length, codes.length);
      for (final c in countries) {
        expect(c.code, matches(RegExp(r'^[A-Z]{2}$')));
        if (c.timeZones.isNotEmpty) {
          expect(
            c.timeZones,
            contains(c.timeZone),
            reason: '${c.code}の候補に既定のタイムゾーンが無い',
          );
        }
      }
      expect(countryByCode('JP')?.ja, '日本');
      expect(countryByCode('XX'), isNull);
    });

    test('都道府県は47件で、コードに重複が無い', () {
      expect(prefectures, hasLength(47));
      expect(prefectures.map((p) => p.code).toSet(), hasLength(47));
      expect(prefectureByCode('JP-13')?.ja, '東京都');
      expect(prefectureByCode('JP-99'), isNull);
    });

    test('代表座標は都道府県があればそちら、無ければ国の首都', () {
      const withPrefecture = Residence(
        countryCode: 'JP',
        prefectureCode: 'JP-01',
      );
      expect(withPrefecture.coordinates?.lat, closeTo(43.06, 0.01));
      const countryOnly = Residence(countryCode: 'FR');
      expect(countryOnly.coordinates?.lat, closeTo(48.9, 0.1));
      expect(countryOnly.effectiveTimeZone, 'Europe/Paris');
      const withZone = Residence(
        countryCode: 'US',
        timeZone: 'America/Los_Angeles',
      );
      expect(withZone.effectiveTimeZone, 'America/Los_Angeles');
    });
  });

  group('ResidenceSurveyScreen', () {
    testWidgets('国を選ぶまで決定ボタンは押せない', (tester) async {
      await _pump(tester, onCompleted: () {});
      final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
      expect(button.onPressed, isNull);
    });

    testWidgets('日本を選ぶと都道府県だけ、時差が複数ある国ではタイムゾーンだけ出る', (tester) async {
      await _pump(tester, onCompleted: () {});

      await _selectCountry(tester, '日本');
      expect(find.text('都道府県（任意）'), findsOneWidget);
      expect(find.text('タイムゾーン（任意）'), findsNothing);

      await tester.tap(find.text('日本'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'アメリカ');
      await tester.pumpAndSettle();
      await tester.tap(find.text('アメリカ合衆国'));
      await tester.pumpAndSettle();
      expect(find.text('都道府県（任意）'), findsNothing);
      expect(find.text('タイムゾーン（任意）'), findsOneWidget);

      await tester.tap(find.text('アメリカ合衆国'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'France');
      await tester.pumpAndSettle();
      await tester.tap(find.text('フランス'));
      await tester.pumpAndSettle();
      expect(find.text('都道府県（任意）'), findsNothing);
      expect(find.text('タイムゾーン（任意）'), findsNothing);
    });

    testWidgets('国だけ選んで決定すると保存して完了を通知する', (tester) async {
      var completed = false;
      final repo = await _pump(tester, onCompleted: () => completed = true);

      await _selectCountry(tester, '日本');
      await tester.tap(find.byType(ElevatedButton));
      await tester.pumpAndSettle();

      expect(completed, isTrue);
      expect(repo.saved['u1'], const Residence(countryCode: 'JP'));
    });

    testWidgets('日本で都道府県を選ぶと一緒に保存される', (tester) async {
      final repo = await _pump(tester, onCompleted: () {});

      await _selectCountry(tester, '日本');
      await tester.tap(find.byKey(const ValueKey('residence-prefecture')));
      await tester.pumpAndSettle();
      // メニューは長い一覧のため、東京都が見える位置までスクロールする。
      await tester.ensureVisible(find.text('東京都'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('東京都'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(ElevatedButton));
      await tester.pumpAndSettle();

      expect(
        repo.saved['u1'],
        const Residence(countryCode: 'JP', prefectureCode: 'JP-13'),
      );
    });

    testWidgets('国と一緒に表示言語を選べて、選ぶとこの画面がその言語に切り替わる', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await _pump(tester, onCompleted: () {});
      expect(find.text('表示言語'), findsOneWidget);
      expect(find.text('国（必須）'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('residence-language')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('English'));
      await tester.pumpAndSettle();
      expect(find.text('Language'), findsOneWidget);
      expect(find.text('Country (required)'), findsOneWidget);
      expect(find.text('国（必須）'), findsNothing);

      // 端末にも保存され、次回起動時にも引き継がれる。
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('appLocaleLanguageCode'), 'en');
    });

    testWidgets('変更時は現在の国が初期表示される', (tester) async {
      await _pump(
        tester,
        onCompleted: () {},
        initial: const Residence(countryCode: 'FR'),
      );
      expect(find.text('フランス'), findsOneWidget);
      expect(find.text('国を選ぶ'), findsNothing);
    });
  });
}
