import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_locale.dart';
import '../../l10n/country_data.dart';
import '../../l10n/prefecture_data.dart';
import '../../l10n/strings.dart';
import '../../models/residence.dart';
import '../../providers/app_locale_provider.dart';
import '../../providers/repository_providers.dart';
import '../../widgets/fixed_font_theme.dart';
import '../../widgets/app_dropdown.dart';

/// 居住地アンケート画面（2026-10-16追加）。新規登録直後、およびまだ回答していない
/// 住人（既存住人・daidai横丁で先にアカウントだけ作った人の初回ログイン後）に、
/// [AuthGate]が必ず通す。設定＞アカウントの「居住地」からの変更にも使う
/// （[initial]を渡し、[isEditing]を`true`にする）。
///
/// 国は必須。日本を選んだ場合のみ都道府県、国内に時差が複数ある国を選んだ場合のみ
/// タイムゾーンを任意で聞く。GPSは使わない自己申告で、保存先は本人のみ読める
/// `users/{uid}/private/residence`。
class ResidenceSurveyScreen extends ConsumerStatefulWidget {
  const ResidenceSurveyScreen({
    required this.userId,
    required this.onCompleted,
    this.initial,
    this.isEditing = false,
    super.key,
  });

  final String userId;

  /// 保存に成功した後に呼ぶ。
  final VoidCallback onCompleted;

  /// 変更時の現在値。
  final Residence? initial;

  /// 設定からの変更時は戻る矢印を出す（初回は回答するまで先へ進めない）。
  final bool isEditing;

  @override
  ConsumerState<ResidenceSurveyScreen> createState() =>
      _ResidenceSurveyScreenState();
}

class _ResidenceSurveyScreenState extends ConsumerState<ResidenceSurveyScreen> {
  String? _countryCode;
  String? _prefectureCode;
  String? _timeZone;

  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial != null) {
      _countryCode = initial.countryCode;
      _prefectureCode = initial.prefectureCode;
      _timeZone = initial.timeZone;
    }
  }

  Country? get _country => countryByCode(_countryCode);

  Future<void> _pickCountry(AppLocale locale) async {
    final picked = await showDialog<String>(
      context: context,
      builder: (_) => _CountryPickerDialog(locale: locale),
    );
    if (picked == null || picked == _countryCode) return;
    setState(() {
      _countryCode = picked;
      // 国が変わったら、前の国に属する都道府県・タイムゾーンは持ち越さない。
      _prefectureCode = null;
      _timeZone = null;
      _errorMessage = null;
    });
  }

  Future<void> _submit() async {
    final strings = ref.read(appStringsProvider);
    final country = _country;
    if (country == null) {
      setState(
        () => _errorMessage = strings.residenceSurveyCountryRequiredError,
      );
      return;
    }
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    try {
      await ref
          .read(residenceRepositoryProvider)
          .saveResidence(
            widget.userId,
            Residence(
              countryCode: country.code,
              prefectureCode: country.code == 'JP' ? _prefectureCode : null,
              timeZone: country.hasMultipleTimeZones ? _timeZone : null,
            ),
          );
      if (!mounted) return;
      widget.onCompleted();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = strings.residenceSurveySaveFailedTemplate(e);
      });
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final locale = ref.watch(appLocaleProvider);
    final country = _country;
    return FixedFontTheme(
      child: Scaffold(
        appBar: AppBar(
          title: Text(strings.residenceSurveyAppBarTitle),
          automaticallyImplyLeading: widget.isEditing,
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 国と一緒に表示言語も選べる（2026-10-17追加）。選ぶとこの画面から
                  // 即座にその言語へ切り替わる（以降の画面・設定にも引き継がれる）。
                  // 言語は今後増える予定のため、並べる形式ではなくプルダウンにする。
                  AppDropdown<AppLocale>(
                    key: const ValueKey('residence-language'),
                    label: strings.residenceSurveyLanguageLabel,
                    value: locale,
                    enabled: !_isSubmitting,
                    items: [
                      for (final l in AppLocale.values)
                        AppDropdownItem(value: l, label: l.label),
                    ],
                    onChanged: (value) =>
                        ref.read(appLocaleProvider.notifier).setLocale(value),
                  ),
                  const SizedBox(height: 16),
                  Text(strings.residenceSurveyIntro),
                  const SizedBox(height: 8),
                  Text(
                    strings.residenceSurveyPrivacyNote,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 16),
                  InkWell(
                    onTap: _isSubmitting ? null : () => _pickCountry(locale),
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: strings.residenceSurveyCountryLabel,
                        border: const OutlineInputBorder(),
                        suffixIcon: const Icon(Icons.arrow_drop_down),
                      ),
                      child: Text(
                        country?.nameOf(locale) ??
                            strings.residenceSurveyCountryPlaceholder,
                      ),
                    ),
                  ),
                  if (country != null && country.code == 'JP') ...[
                    const SizedBox(height: 16),
                    AppDropdown<String?>(
                      key: const ValueKey('residence-prefecture'),
                      label: strings.residenceSurveyPrefectureLabel,
                      placeholder: strings.residenceSurveyNotSelected,
                      value: _prefectureCode,
                      enabled: !_isSubmitting,
                      items: [
                        AppDropdownItem(
                          value: null,
                          label: strings.residenceSurveyNotSelected,
                        ),
                        for (final p in prefectures)
                          AppDropdownItem(
                            value: p.isoCode,
                            label: p.nameOf(locale),
                          ),
                      ],
                      onChanged: (value) =>
                          setState(() => _prefectureCode = value),
                    ),
                  ],
                  if (country != null && country.hasMultipleTimeZones) ...[
                    const SizedBox(height: 16),
                    AppDropdown<String?>(
                      key: ValueKey('residence-timezone-${country.code}'),
                      label: strings.residenceSurveyTimeZoneLabel,
                      placeholder: strings.residenceSurveyNotSelected,
                      value: _timeZone,
                      enabled: !_isSubmitting,
                      items: [
                        AppDropdownItem(
                          value: null,
                          label: strings.residenceSurveyNotSelected,
                        ),
                        for (final tz in country.timeZones)
                          AppDropdownItem(value: tz, label: tz),
                      ],
                      onChanged: (value) => setState(() => _timeZone = value),
                    ),
                  ],
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _errorMessage!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ],
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _isSubmitting || country == null
                        ? null
                        : _submit,
                    child: _isSubmitting
                        ? const SizedBox.shrink()
                        : Text(strings.residenceSurveySubmitButton),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 国名で絞り込める選択ダイアログ。選んだ国のISOコードを返す。
class _CountryPickerDialog extends ConsumerStatefulWidget {
  const _CountryPickerDialog({required this.locale});

  final AppLocale locale;

  @override
  ConsumerState<_CountryPickerDialog> createState() =>
      _CountryPickerDialogState();
}

class _CountryPickerDialogState extends ConsumerState<_CountryPickerDialog> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final query = _query.trim().toLowerCase();
    // 日本語・英語・表示言語のどの名前でも、コードでも絞り込める。
    final filtered = [
      for (final c in countries)
        if (query.isEmpty ||
            c
                .searchNames(widget.locale)
                .any((name) => name.toLowerCase().contains(query)) ||
            c.code.toLowerCase() == query)
          c,
    ];
    return AlertDialog(
      title: Text(strings.residenceSurveyCountryLabel),
      content: SizedBox(
        width: 360,
        height: 440,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              decoration: InputDecoration(
                hintText: strings.residenceSurveySearchHint,
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: filtered.isEmpty
                  ? Center(child: Text(strings.residenceSurveyNoResults))
                  : ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final c = filtered[index];
                        return ListTile(
                          title: Text(c.nameOf(widget.locale)),
                          onTap: () => Navigator.of(context).pop(c.code),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
