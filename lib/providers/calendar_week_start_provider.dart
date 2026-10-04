import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/calendar_week_start.dart';
import 'repository_providers.dart';

const _prefsKey = 'calendarWeekStart';

/// 端末に保存されている初期のカレンダーの週の始まり。main()で起動前に読み込み、
/// ProviderScopeのoverrideとして渡す。
final initialCalendarWeekStartProvider = Provider<CalendarWeekStart>((ref) {
  throw UnimplementedError('main()でoverrideすること');
});

Future<CalendarWeekStart> loadInitialCalendarWeekStart() async {
  final prefs = await SharedPreferences.getInstance();
  return CalendarWeekStart.fromName(prefs.getString(_prefsKey));
}

class CalendarWeekStartNotifier extends Notifier<CalendarWeekStart> {
  @override
  CalendarWeekStart build() => ref.watch(initialCalendarWeekStartProvider);

  Future<void> setWeekStart(CalendarWeekStart weekStart) async {
    state = weekStart;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, weekStart.name);
    final userId = ref.read(authStateProvider).value?.uid;
    if (userId == null) return;
    await ref
        .read(userRepositoryProvider)
        .updateUserPreference(userId, 'calendarWeekStart', weekStart.name);
  }

  /// ログイン時、Firestoreに保存されている値で端末側を上書きする
  /// （既にFirestore側にある値の書き戻しは行わない）。
  Future<void> syncFromRemote(CalendarWeekStart weekStart) async {
    state = weekStart;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, weekStart.name);
  }
}

final calendarWeekStartProvider =
    NotifierProvider<CalendarWeekStartNotifier, CalendarWeekStart>(
      CalendarWeekStartNotifier.new,
    );
