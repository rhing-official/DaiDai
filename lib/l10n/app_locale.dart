import 'package:flutter/widgets.dart';

/// アプリの表示言語。既定は日本語、もう一つはイギリス英語。
enum AppLocale {
  japanese('ja', null, '日本語'),
  britishEnglish('en', 'GB', 'English');

  const AppLocale(this.languageCode, this.countryCode, this.label);

  final String languageCode;
  final String? countryCode;
  final String label;

  Locale get locale => Locale(languageCode, countryCode);

  static AppLocale fromLanguageCode(String? code) {
    return values.firstWhere(
      (l) => l.languageCode == code,
      orElse: () => AppLocale.japanese,
    );
  }
}
