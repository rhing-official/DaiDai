import 'package:daidai/features/not_found/not_found_screen.dart';
import 'package:daidai/l10n/app_locale.dart';
import 'package:daidai/l10n/country_data.dart';
import 'package:daidai/l10n/guide_content.dart';
import 'package:daidai/l10n/prefecture_data.dart';
import 'package:daidai/l10n/strings.dart';
import 'package:daidai/l10n/vocabulary.dart';
import 'package:daidai/models/font_design.dart';
import 'package:daidai/utils/message_time.dart';
import 'package:flutter_test/flutter_test.dart';

// 表示言語を足したときに、対訳データの抜けを自動で検出するテスト（2026-10-17）。
// `AppLocale.values`を全て回すため、新しい言語を追加すると、その言語の
// 画面の文言・用語・国名・ガイド・404の展示文・曜日・フォントがそろっていないと落ちる。
// 日本語・英語以外の言語は、日英が基準の元データに対する「訳」として網羅を確認する。

bool _isTranslation(AppLocale l) =>
    l != AppLocale.japanese && l != AppLocale.britishEnglish;

void main() {
  for (final locale in AppLocale.values) {
    group('${locale.languageCode}${locale.countryCode ?? ''}', () {
      test('ラベル・言語コードが空でない', () {
        expect(locale.label.trim(), isNotEmpty);
        expect(locale.languageCode, matches(RegExp(r'^[a-z]{2}$')));
        expect(AppLocale.fromLanguageCode(locale.languageCode), locale);
      });

      test('画面の文言（Strings）と用語（Vocabulary）が引ける', () {
        final strings = Strings.of(locale);
        for (final font in FontDesign.values) {
          expect(strings.fontDesignLabel(font).trim(), isNotEmpty);
        }
        final vocab = Vocabulary.of(locale);
        for (final term in [
          vocab.dm,
          vocab.plaza,
          vocab.profileStorage,
          vocab.profileCreator,
          vocab.textChannel,
          vocab.nickname,
          vocab.statusMessage,
          vocab.friendConnect,
          vocab.owner,
          vocab.sticker,
        ]) {
          expect(term.trim(), isNotEmpty);
        }
      });

      test('国名が全ての国で空でなく、訳の言語では日英と別に全コードを持つ', () {
        for (final country in countries) {
          expect(
            country.nameOf(locale).trim(),
            isNotEmpty,
            reason: country.code,
          );
        }
        if (_isTranslation(locale)) {
          final names = countryNamesOf(locale);
          expect(names, isNotNull, reason: '国名の対応表が無い');
          for (final country in countries) {
            expect(names![country.code], isNotNull, reason: country.code);
          }
          expect(names!.length, countries.length);
        }
        for (final prefecture in prefectures) {
          expect(prefecture.nameOf(locale).trim(), isNotEmpty);
        }
      });

      test('使い方ガイドが全ての機能別ガイドで引ける', () {
        for (final topic in guideTopics) {
          expect(topic.titleOf(locale).trim(), isNotEmpty);
          expect(topic.summaryOf(locale).trim(), isNotEmpty);
          expect(topic.stepsOf(locale), hasLength(topic.steps.length));
        }
        if (_isTranslation(locale)) {
          final translation = guideTranslationOf(locale);
          expect(translation, isNotNull, reason: 'ガイドの訳が無い');
          for (final topic in guideTopics) {
            final text = translation!.topics[topic.id];
            expect(text, isNotNull, reason: topic.id);
            expect(text!.steps.length, topic.steps.length, reason: topic.id);
          }
        }
      });

      test('404の展示文が全作品で引ける', () {
        for (final exhibit in museumExhibits) {
          expect(exhibit.titleFor(locale).trim(), isNotEmpty);
          expect(exhibit.captionFor(locale).trim(), isNotEmpty);
        }
        if (_isTranslation(locale)) {
          final texts = museumTextsOf(locale);
          expect(texts, isNotNull, reason: '展示文の訳が無い');
          for (final exhibit in museumExhibits) {
            expect(texts![exhibit.asset], isNotNull, reason: exhibit.asset);
          }
        }
      });

      test('曜日つきの日付が整形できる', () {
        final text = formatMessageDate(DateTime(2026, 10, 12), locale);
        expect(text, startsWith('2026/10/12 ('));
      });
    });
  }

  test('神楽坂ドットは日本語・英語でだけ選べ、それ以外は既定のフォントに置き換わる', () {
    for (final locale in AppLocale.values) {
      final supported = !_isTranslation(locale);
      expect(
        FontDesign.availableFor(locale).contains(FontDesign.kagurazaka),
        supported,
        reason: locale.languageCode,
      );
      expect(
        FontDesign.kagurazaka.resolvedFor(locale),
        supported ? FontDesign.kagurazaka : FontDesign.notoSansJp,
      );
      // 他のフォントは全言語でそのまま使える。
      expect(FontDesign.kiwiMaru.resolvedFor(locale), FontDesign.kiwiMaru);
    }
  });
}
