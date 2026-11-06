import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/holiday_data.dart';
import '../l10n/japan_holidays.dart';
import '../l10n/observances.dart';
import '../l10n/religious_holidays.dart';
import 'repository_providers.dart';

const _regionsKey = 'holidayRegions';
const _observancesKey = 'holidayObservances';
const _religionsKey = 'holidayReligions';

/// 祝日データのある国（地域の祝日のチェックボックスに並べる）。今は日本だけ。
const kHolidayRegions = ['JP'];

/// カレンダーに出す祝日・祭日・宗教上の祝日の選択（2026-11-05追加）。端末とアカウントの両方に保存する。
class HolidaySettings {
  const HolidaySettings({
    this.regions,
    this.observances = true,
    this.religions = const {},
  });

  /// 表示する地域（国コード）。nullなら居住国（未選択は日本）に従う。
  final Set<String>? regions;

  /// 世界共通の行事（祭日）を出すか。
  final bool observances;

  /// 表示する宗教（`kReligions`の値）。
  final Set<String> religions;

  HolidaySettings copyWith({
    Set<String>? regions,
    bool? observances,
    Set<String>? religions,
  }) => HolidaySettings(
    regions: regions ?? this.regions,
    observances: observances ?? this.observances,
    religions: religions ?? this.religions,
  );

  /// 語らい毎の上書きとして保存する形（3項目全てを持つ。regionsがnull＝居住国に従う
  /// 場合は、regionsを書かない）。
  Map<String, dynamic> toOverrideJson() => {
    if (regions != null) 'regions': regions!.toList(),
    'observances': observances,
    'religions': religions.toList(),
  };

  factory HolidaySettings.fromOverrideJson(Map<String, dynamic> json) {
    return HolidaySettings(
      regions: (json['regions'] as List?)?.cast<String>().toSet(),
      observances: json['observances'] as bool? ?? true,
      religions: ((json['religions'] as List?)?.cast<String>() ?? const [])
          .toSet(),
    );
  }

  /// 実際に使う地域。未設定なら[residenceCountry]。
  Set<String> effectiveRegions(String residenceCountry) =>
      regions ?? {residenceCountry};
}

/// [day]に出す祝日・祭日・宗教上の祝日。順番は、祝日、祭日、宗教。
List<HolidayEntry> holidaysFor(
  DateTime day,
  HolidaySettings settings,
  String residenceCountry,
) {
  final result = <HolidayEntry>[];
  if (settings.effectiveRegions(residenceCountry).contains('JP')) {
    final jp = japanHolidayEntryOf(day);
    if (jp != null) result.add(jp);
  }
  if (settings.observances) result.addAll(observancesOn(day));
  if (settings.religions.isNotEmpty) {
    result.addAll(religiousHolidaysOn(day, settings.religions));
  }
  return result;
}

final initialHolidaySettingsProvider = Provider<HolidaySettings>((ref) {
  throw UnimplementedError('main()でoverrideすること');
});

Future<HolidaySettings> loadInitialHolidaySettings() async {
  final prefs = await SharedPreferences.getInstance();
  final regions = prefs.getStringList(_regionsKey);
  return HolidaySettings(
    regions: regions?.toSet(),
    observances: prefs.getBool(_observancesKey) ?? true,
    religions: (prefs.getStringList(_religionsKey) ?? const []).toSet(),
  );
}

class HolidaySettingsNotifier extends Notifier<HolidaySettings> {
  @override
  HolidaySettings build() => ref.watch(initialHolidaySettingsProvider);

  Future<void> setRegion(
    String country,
    bool enabled,
    String residenceCountry,
  ) async {
    final regions = {...state.effectiveRegions(residenceCountry)};
    enabled ? regions.add(country) : regions.remove(country);
    state = state.copyWith(regions: regions);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_regionsKey, regions.toList());
    await _saveRemote('holidayRegions', regions.toList());
  }

  Future<void> setObservances(bool enabled) async {
    state = state.copyWith(observances: enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_observancesKey, enabled);
    await _saveRemote('holidayObservances', enabled);
  }

  Future<void> setReligion(String religion, bool enabled) async {
    final religions = {...state.religions};
    enabled ? religions.add(religion) : religions.remove(religion);
    state = state.copyWith(religions: religions);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_religionsKey, religions.toList());
    await _saveRemote('holidayReligions', religions.toList());
  }

  /// アカウントにも保存する（別の端末でも同じ選択になる）。
  Future<void> _saveRemote(String field, Object value) async {
    final userId = ref.read(authStateProvider).value?.uid;
    if (userId == null) return;
    await ref
        .read(userRepositoryProvider)
        .updateUserPreference(userId, field, value);
  }

  /// ログイン時、アカウントに保存されている値で端末側を上書きする
  /// （書き戻しは行わない）。アカウント側に無い項目は端末の値のまま。
  Future<void> syncFromRemote({
    Set<String>? regions,
    bool? observances,
    Set<String>? religions,
  }) async {
    state = state.copyWith(
      regions: regions,
      observances: observances,
      religions: religions,
    );
    final prefs = await SharedPreferences.getInstance();
    if (regions != null) {
      await prefs.setStringList(_regionsKey, regions.toList());
    }
    if (observances != null) await prefs.setBool(_observancesKey, observances);
    if (religions != null) {
      await prefs.setStringList(_religionsKey, religions.toList());
    }
  }
}

final holidaySettingsProvider =
    NotifierProvider<HolidaySettingsNotifier, HolidaySettings>(
      HolidaySettingsNotifier.new,
    );
