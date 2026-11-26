import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_ui_style.dart';
import '../theme/block/block_tokens.dart';
import '../theme_pack/firebase_owned_theme_pack_source.dart';
import '../theme_pack/owned_theme_pack_repository.dart';
import '../theme_pack/theme_pack.dart';
import '../theme_pack/theme_pack_cache.dart';
import '../theme_pack/theme_pack_repository.dart';
import 'app_ui_style_provider.dart';
import 'repository_providers.dart';

const _prefsKey = 'themePackId';

/// 横丁で取得した意匠。未ログインの時は、端末に置いた素材だけを読む。
final themePackRepositoryProvider = Provider<ThemePackRepository>((ref) {
  final uid = ref.watch(authStateProvider).value?.uid;
  return OwnedThemePackRepository(
    source: uid == null ? null : FirebaseOwnedThemePackSource(userId: uid),
    cache: createThemePackFileCache(),
  );
});

/// 今適用している素材パックと、読めずに標準へ戻した理由。
class ThemePackState {
  const ThemePackState({
    this.pack,
    this.fallbackReason,
    this.suspended = false,
  });
  final ThemePack? pack;

  /// 適用していた意匠の配信が停止され、標準の版画へ戻した。
  final bool suspended;

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
  // 同梱の公式パックは廃止した。昔の選択は理由を出さずに外し、標準の版画で起動する。
  if (!isOwnedThemePackId(id)) {
    await prefs.remove(_prefsKey);
    return const ThemePackState();
  }
  // 版画以外のスタイルが選ばれているなら、パックは使わない。
  if (AppUiStyle.fromName(prefs.getString('appUiStyle')) != AppUiStyle.block) {
    return const ThemePackState();
  }
  // 起動は端末に置いた素材だけで即時に適用する。通信を伴う確認は、認証が確定した後。
  final state = await _tryLoad(
    repository ?? OwnedThemePackRepository(cache: createThemePackFileCache()),
    id,
  );
  _applyTokens(state.pack);
  return state;
}

Future<ThemePackState> _tryLoad(ThemePackRepository repo, String id) async {
  try {
    return ThemePackState(pack: await repo.load(id));
  } on ThemePackNotCachedException {
    // 端末に素材が無いだけ。理由は出さず、保存した選択も消さない。
    return const ThemePackState();
  } on ThemePackSuspendedException {
    return const ThemePackState(suspended: true);
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
  ThemePackState build() {
    // 認証が確定したら、取得済みの意匠の状態を1回確かめる。
    ref.listen(authStateProvider, (_, next) {
      if (next.value != null) verify();
    });
    return ref.watch(initialThemePackProvider);
  }

  /// 取得済みの意匠が配信停止なら、標準の版画へ戻す。起動後と、設定を開いた時に呼ぶ。
  /// 取り下げ済みは、取得済みの人が使い続けられるので何もしない。
  /// 通信できない時は、前に使った意匠をそのまま使う。
  Future<void> verify() async {
    final prefs = await SharedPreferences.getInstance();
    final id = state.pack?.id ?? prefs.getString(_prefsKey);
    if (id == null || !isOwnedThemePackId(id)) return;
    if (ref.read(appUiStyleProvider) != AppUiStyle.block) return;
    try {
      final pack = await ref.read(themePackRepositoryProvider).load(id);
      if (state.pack == null) {
        // Webの再読み込み後など、端末に素材が無かった時は、ここで適用する。
        _applyTokens(pack);
        state = ThemePackState(pack: pack);
      }
    } on ThemePackSuspendedException {
      _applyTokens(null);
      state = const ThemePackState(suspended: true);
      await prefs.remove(_prefsKey);
    } catch (_) {
      // 読めない理由が通信なら、そのまま。
    }
  }

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
    if (state.pack == null &&
        state.fallbackReason == null &&
        !state.suspended) {
      return;
    }
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
