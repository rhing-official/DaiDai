import 'package:flutter_test/flutter_test.dart';

import 'package:daidai/l10n/app_locale.dart';
import 'package:daidai/models/app_user.dart';
import 'package:daidai/models/profile_card.dart';
import 'package:daidai/models/profile_material.dart';
import 'package:daidai/utils/birthday_format.dart';

void main() {
  final now = DateTime(2026, 10, 23);

  group('Birthday.isValid', () {
    test('存在しない日付は不可', () {
      expect(const Birthday(month: 2, day: 30).isValid(now: now), isFalse);
      expect(const Birthday(month: 4, day: 31).isValid(now: now), isFalse);
      expect(const Birthday(month: 13, day: 1).isValid(now: now), isFalse);
      expect(const Birthday(month: 1, day: 0).isValid(now: now), isFalse);
    });

    test('年が無ければ2月29日は可、年があれば閏年だけ可', () {
      expect(const Birthday(month: 2, day: 29).isValid(now: now), isTrue);
      expect(
        const Birthday(year: 2000, month: 2, day: 29).isValid(now: now),
        isTrue,
      );
      expect(
        const Birthday(year: 2001, month: 2, day: 29).isValid(now: now),
        isFalse,
      );
      expect(
        const Birthday(year: 1900, month: 2, day: 29).isValid(now: now),
        isFalse,
      );
    });

    test('年は1900年から今年まで（未来は不可）', () {
      expect(
        const Birthday(year: 1899, month: 1, day: 1).isValid(now: now),
        isFalse,
      );
      expect(
        const Birthday(year: 2026, month: 1, day: 1).isValid(now: now),
        isTrue,
      );
      expect(
        const Birthday(year: 2027, month: 1, day: 1).isValid(now: now),
        isFalse,
      );
    });
  });

  group('JSON', () {
    test('往復し、年が無ければキーも書かない', () {
      const withYear = Birthday(year: 2000, month: 1, day: 23);
      expect(Birthday.fromJson(withYear.toJson()), withYear);
      const noYear = Birthday(month: 1, day: 23);
      expect(noYear.toJson().containsKey('year'), isFalse);
      expect(Birthday.fromJson(noYear.toJson()), noYear);
    });

    test('欠損・不正な値はnull', () {
      expect(Birthday.fromJson(null), isNull);
      expect(Birthday.fromJson({'month': 2, 'day': 30}), isNull);
      expect(Birthday.fromJson({'month': 'a', 'day': 1}), isNull);
    });

    test('AppUserとProfileCardの誕生日の項目が往復する', () {
      const user = AppUser(
        userId: 'u',
        rhingSeed: 's',
        birthday: Birthday(month: 1, day: 23),
      );
      expect(
        AppUser.fromJson(user.toJson()).birthday,
        const Birthday(month: 1, day: 23),
      );
      const off = ProfileCard(id: 'c', name: 'n');
      expect(off.toJson().containsKey('showBirthday'), isFalse);
      expect(ProfileCard.fromJson(off.toJson()).showBirthday, isFalse);
      final on = off.copyWith(showBirthday: true);
      expect(ProfileCard.fromJson(on.toJson()).showBirthday, isTrue);
    });
  });

  test('カードで載せる設定の時だけ、閲覧側に誕生日が出る', () {
    const card = ProfileCard(id: 'c', name: 'n');
    const birthday = Birthday(month: 1, day: 23);
    final hidden = const AppUser(
      userId: 'u',
      rhingSeed: 's',
      birthday: birthday,
      profileCards: [card],
      activeProfileCardId: 'c',
    );
    expect(hidden.effectiveBirthdayFor(null), isNull);
    final shown = hidden.copyWith(
      profileCards: [card.copyWith(showBirthday: true)],
    );
    expect(shown.effectiveBirthdayFor(null), birthday);
    expect(shown.effectiveBirthday, birthday);
  });

  group('表記と並び', () {
    const full = Birthday(year: 2000, month: 1, day: 23);
    const noYear = Birthday(month: 1, day: 23);

    test('日本語は年月日、英語・フランス語は日月年', () {
      expect(formatBirthday(full, AppLocale.japanese), '2000年1月23日');
      expect(formatBirthday(noYear, AppLocale.japanese), '1月23日');
      expect(formatBirthday(full, AppLocale.britishEnglish), '23 January 2000');
      expect(formatBirthday(noYear, AppLocale.britishEnglish), '23 January');
      expect(formatBirthday(full, AppLocale.french), '23 janvier 2000');
      expect(formatBirthday(noYear, AppLocale.french), '23 janvier');
    });

    test('入力欄の並び', () {
      expect(birthdayFieldOrder(AppLocale.japanese), [
        BirthdayField.year,
        BirthdayField.month,
        BirthdayField.day,
      ]);
      expect(birthdayFieldOrder(AppLocale.britishEnglish), [
        BirthdayField.day,
        BirthdayField.month,
        BirthdayField.year,
      ]);
      expect(birthdayFieldOrder(AppLocale.french).first, BirthdayField.day);
    });
  });
}
