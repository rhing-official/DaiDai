import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_ui_style.dart';
import '../theme/block/block_tokens.dart';
import '../theme_pack/theme_pack.dart';
import '../theme_pack/theme_pack_repository.dart';
import 'app_ui_style_provider.dart';

const _prefsKey = 'themePackId';

final themePackRepositoryProvider = Provider<ThemePackRepository>(
  (ref) => BundledThemePackRepository(),
);

/// 今適用している素材パックと、読めずに標準へ戻した理由。
class ThemePackState {
  const ThemePackState({this.pack, this.fallbackReason});
  final ThemePack? pack;

  /// 選んだパックを読めず、標準の版画へ戻した時の理由（設定画面に1行出す）。
  final String? fallbackReason;
}

/// main()で起動前に読んだ、初期のパック。overrideされない場合（テスト等）は、パック無し。
final initialThemePackProvider = Provider<ThemePackState>(
  (ref) => const ThemePackState(),
);

/// 起動時に、保存されたパックを読む。読めなければ標準へ戻す（理由を残す）。
Future<ThemePackState> loadInitialThemePack({
  ThemePackRepository? repository,
}) async {
  final prefs = await SharedPreferences.getInstance();
  final id = prefs.getString(_prefsKey);
  if (id == null) return const ThemePackState();
  // 版画以外のスタイルが選ばれているなら、パックは使わない。
  if (AppUiStyle.fromName(prefs.getString('appUiStyle')) != AppUiStyle.block) {
    return const ThemePackState();
  }
  final state = await _tryLoad(repository ?? BundledThemePackRepository(), id);
  _applyTokens(state.pack);
  return state;
}

Future<ThemePackState> _tryLoad(ThemePackRepository repo, String id) async {
  try {
    return ThemePackState(pack: await repo.load(id));
  } on ThemePackException catch (e) {
    return ThemePackState(fallbackReason: e.reason);
  } catch (_) {
    return const ThemePackState(fallbackReason: 'パックを読み込めませんでした');
  }
}

void _applyTokens(ThemePack? pack) {
  BlockTokens.current = pack?.tokens ?? const BlockTokens();
}

class ThemePackNotifier extends Notifier<ThemePackState> {
  @override
  ThemePackState build() => ref.watch(initialThemePackProvider);

  /// パックを選ぶ。パックは版画の部品に流し込むので、UIスタイルも版画にする。
  /// 読めなければ標準の版画に戻し、理由を残す。
  Future<void> select(String id) async {
    final next = await _tryLoad(ref.read(themePackRepositoryProvider), id);
    _applyTokens(next.pack);
    state = next;
    final prefs = await SharedPreferences.getInstance();
    if (next.pack != null) {
      await prefs.setString(_prefsKey, id);
    } else {
      await prefs.remove(_prefsKey);
    }
    await ref.read(appUiStyleProvider.notifier).setStyle(AppUiStyle.block);
  }

  /// パックを外す（UIスタイルは変えない）。
  Future<void> clear() async {
    if (state.pack == null && state.fallbackReason == null) return;
    _applyTokens(null);
    state = const ThemePackState();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }
}

final themePackProvider = NotifierProvider<ThemePackNotifier, ThemePackState>(
  ThemePackNotifier.new,
);

/// 使えるパックの一覧。
final themePackListProvider = FutureProvider<List<ThemePackSummary>>(
  (ref) => ref.watch(themePackRepositoryProvider).list(),
);
