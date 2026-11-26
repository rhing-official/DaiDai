import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'repository_providers.dart';

const _prefsKey = 'selectionMotion';

/// 旧: 水で移すか（オン/オフ）。[SelectionMotion]へ引き継ぐ。
const _legacyPrefsKey = 'selectionWaterMotion';

/// 選択の動き（2026-11-26）。メニューチップの帯の構造も、この値で決まる。
enum SelectionMotion {
  /// チップを1つずつ分けて、選択色が水のように流れ込む。
  liquid,

  /// 帯を1本にして、選択中を丸で囲む。丸が次の項目へ滑る。
  ring,

  /// チップを1つずつ分けて、選択色は即時に切り替わる。
  none;

  static SelectionMotion? parse(String? name) {
    for (final v in values) {
      if (v.name == name) return v;
    }
    return null;
  }

  /// 旧い保存値（水で移す=true）から。
  static SelectionMotion fromLegacy(bool water) => water ? liquid : none;
}

/// 端末に保存されている初期値。端末の「動きを減らす」設定には関係なく、保存が無い時は液体
/// （2026-11-26、ユーザー指示。アプリ全体のアニメーションと同じ方針）。
final initialSelectionMotionProvider = Provider<SelectionMotion>(
  (ref) => SelectionMotion.liquid,
);

Future<SelectionMotion> loadInitialSelectionMotion() async {
  final prefs = await SharedPreferences.getInstance();
  final saved = SelectionMotion.parse(prefs.getString(_prefsKey));
  if (saved != null) return saved;
  final legacy = prefs.getBool(_legacyPrefsKey);
  return legacy == null
      ? SelectionMotion.liquid
      : SelectionMotion.fromLegacy(legacy);
}

class SelectionMotionNotifier extends Notifier<SelectionMotion> {
  @override
  SelectionMotion build() => ref.watch(initialSelectionMotionProvider);

  Future<void> setMotion(SelectionMotion motion) async {
    state = motion;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, motion.name);
    final userId = ref.read(authStateProvider).value?.uid;
    if (userId == null) return;
    await ref
        .read(userRepositoryProvider)
        .updateUserPreference(userId, 'selectionMotion', motion.name);
  }

  /// ログイン時、Firestoreに保存されている値で端末側を上書きする。
  Future<void> syncFromRemote(SelectionMotion motion) async {
    state = motion;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, motion.name);
  }
}

final selectionMotionProvider =
    NotifierProvider<SelectionMotionNotifier, SelectionMotion>(
      SelectionMotionNotifier.new,
    );

/// 選択色を、水が流れ込むように移すか（液体の時だけ）。設定・身だしなみの一覧、語らいのタブ、
/// 分けたメニューチップが見る。丸で囲む時・なしの時は、これらは即時に切り替わる。
final selectionWaterMotionProvider = Provider<bool>(
  (ref) => ref.watch(selectionMotionProvider) == SelectionMotion.liquid,
);

/// メニューチップの選択色を、水が流れ込むように移すか（液体の時だけ。丸で囲む時は、丸が滑る）。
final navWaterMotionProvider = Provider<bool>(
  (ref) => ref.watch(selectionMotionProvider) == SelectionMotion.liquid,
);

/// メニューチップの帯を1本にするか（丸で囲む時だけ）。分ける時は、チップが1つずつ独立する。
final navBandMergedProvider = Provider<bool>(
  (ref) => ref.watch(selectionMotionProvider) == SelectionMotion.ring,
);
