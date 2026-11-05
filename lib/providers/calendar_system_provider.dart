import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/calendar_system.dart';
import '../models/calendar_week_start.dart';
import 'calendar_week_start_provider.dart';
import 'holiday_settings_provider.dart';
import 'conversation_prefs_providers.dart';
import 'repository_providers.dart';

const _prefsKey = 'calendarSystem';

/// 端末に保存されている全体の暦。main()で起動前に読み込み、overrideとして渡す。
/// 端末とアカウントの両方に保存する（別の端末でも同じ暦になる）。
final initialCalendarSystemProvider = Provider<CalendarSystem>((ref) {
  throw UnimplementedError('main()でoverrideすること');
});

Future<CalendarSystem> loadInitialCalendarSystem() async {
  final prefs = await SharedPreferences.getInstance();
  return CalendarSystem.fromName(prefs.getString(_prefsKey));
}

class CalendarSystemNotifier extends Notifier<CalendarSystem> {
  @override
  CalendarSystem build() => ref.watch(initialCalendarSystemProvider);

  Future<void> setSystem(CalendarSystem system) async {
    state = system;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, system.name);
    final userId = ref.read(authStateProvider).value?.uid;
    if (userId == null) return;
    await ref
        .read(userRepositoryProvider)
        .updateUserPreference(userId, 'calendarSystem', system.name);
  }

  /// ログイン時、アカウントに保存されている値で端末側を上書きする
  /// （書き戻しは行わない）。
  Future<void> syncFromRemote(CalendarSystem system) async {
    state = system;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, system.name);
  }
}

final calendarSystemProvider =
    NotifierProvider<CalendarSystemNotifier, CalendarSystem>(
      CalendarSystemNotifier.new,
    );

/// 語らいごとの暦の上書き（自分だけに効く。未設定ならnull＝全体の暦に従う）。
final conversationCalendarSystemProvider =
    Provider.family<CalendarSystem?, String>((ref, conversationId) {
      final userId = ref.watch(authStateProvider).value?.uid;
      if (userId == null) return null;
      final prefs = ref.watch(conversationPrefsProvider(userId)).value;
      return CalendarSystem.tryFromName(prefs?[conversationId]?.calendarSystem);
    });

/// その語らいで実際に使う暦。優先順位は、語らいごとの設定、全体の設定。
final effectiveCalendarSystemProvider = Provider.family<CalendarSystem, String>(
  (ref, conversationId) {
    return ref.watch(conversationCalendarSystemProvider(conversationId)) ??
        ref.watch(calendarSystemProvider);
  },
);

/// 祝日を決める国（居住国）。居住地が未選択・取得できない時は日本。
final holidayCountryProvider = FutureProvider<String>((ref) async {
  final userId = ref.watch(authStateProvider).value?.uid;
  if (userId == null) return 'JP';
  try {
    final residence = await ref
        .watch(residenceRepositoryProvider)
        .getResidence(userId);
    final code = residence?.countryCode;
    return (code == null || code.isEmpty) ? 'JP' : code.toUpperCase();
  } catch (_) {
    return 'JP';
  }
});

/// 語らいごとの週の始まりの上書き（未設定ならnull＝標準に従う）。
final conversationWeekStartProvider =
    Provider.family<CalendarWeekStart?, String>((ref, conversationId) {
      final userId = ref.watch(authStateProvider).value?.uid;
      if (userId == null) return null;
      final name = ref
          .watch(conversationPrefsProvider(userId))
          .value?[conversationId]
          ?.calendarWeekStart;
      return name == null ? null : CalendarWeekStart.fromName(name);
    });

/// その語らいで実際に使う週の始まり。優先順位は、語らいごとの設定、標準。
final effectiveWeekStartProvider = Provider.family<CalendarWeekStart, String>((
  ref,
  conversationId,
) {
  return ref.watch(conversationWeekStartProvider(conversationId)) ??
      ref.watch(calendarWeekStartProvider);
});

/// 語らいごとの祝日・祭日・宗教の上書き（未設定ならnull＝標準に従う）。
/// 上書きするときは3項目すべてを持つ（[HolidaySettings.toOverrideJson]）。
final conversationHolidayOverrideProvider =
    Provider.family<HolidaySettings?, String>((ref, conversationId) {
      final userId = ref.watch(authStateProvider).value?.uid;
      if (userId == null) return null;
      final json = ref
          .watch(conversationPrefsProvider(userId))
          .value?[conversationId]
          ?.holidayOverride;
      return json == null ? null : HolidaySettings.fromOverrideJson(json);
    });

/// その語らいで実際に使う祝日・祭日・宗教の選択。
final effectiveHolidaySettingsProvider =
    Provider.family<HolidaySettings, String>((ref, conversationId) {
      return ref.watch(conversationHolidayOverrideProvider(conversationId)) ??
          ref.watch(holidaySettingsProvider);
    });
