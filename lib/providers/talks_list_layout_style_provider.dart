import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/talks_list_layout_style.dart';

const _prefsKey = 'talksListLayoutStyle';

/// 横画面（タブレットの横向き等、`talks_tab.dart`の`isTalksSplitLayout`が
/// true）用の語らい一覧レイアウト保存キー（2026-11-23追加）。タブレットは
/// 縦画面・横画面で見た目の最適解が異なる為、ナビチップの揃え
/// （`navChipAlignment`/`navChipAlignmentWide`）と同じ命名・考え方で、
/// 縦画面用（[_prefsKey]）と別に保存する。
const _wideKey = 'talksListLayoutStyleWide';

/// 端末に保存されている初期の語らい一覧レイアウト（縦画面用）。アカウントには保存せず端末毎に持つ
/// （2026-11-01、ユーザー指示。端末の画面の大きさで向く並びが違うため）。main()で起動前に読み込み、
/// ProviderScopeのoverrideとして渡す。
final initialTalksListLayoutStyleProvider = Provider<TalksListLayoutStyle>((
  ref,
) {
  throw UnimplementedError('main()でoverrideすること');
});

/// 端末に保存されている初期の語らい一覧レイアウト（横画面用、2026-11-23追加）。
/// [initialTalksListLayoutStyleProvider]と同じくアカウント非同期・端末保存。
final initialTalksListLayoutStyleWideProvider = Provider<TalksListLayoutStyle>((
  ref,
) {
  throw UnimplementedError('main()でoverrideすること');
});

Future<TalksListLayoutStyle> loadInitialTalksListLayoutStyle() async {
  final prefs = await SharedPreferences.getInstance();
  return TalksListLayoutStyle.fromName(prefs.getString(_prefsKey));
}

/// 横画面用の値を読み込む（2026-11-23追加）。横画面用のキーをまだ保存した
/// ことが無い端末（この機能を追加する前から使っている端末）は、縦画面用の
/// 値をそのまま引き継ぐ（ナビチップの`wideAlignment`の移行と同じ考え方）。
Future<TalksListLayoutStyle> loadInitialTalksListLayoutStyleWide() async {
  final prefs = await SharedPreferences.getInstance();
  if (prefs.containsKey(_wideKey)) {
    return TalksListLayoutStyle.fromName(prefs.getString(_wideKey));
  }
  return TalksListLayoutStyle.fromName(prefs.getString(_prefsKey));
}

class TalksListLayoutStyleNotifier extends Notifier<TalksListLayoutStyle> {
  @override
  TalksListLayoutStyle build() =>
      ref.watch(initialTalksListLayoutStyleProvider);

  Future<void> setStyle(TalksListLayoutStyle style) async {
    state = style;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, style.name);
  }
}

final talksListLayoutStyleProvider =
    NotifierProvider<TalksListLayoutStyleNotifier, TalksListLayoutStyle>(
      TalksListLayoutStyleNotifier.new,
    );

/// 横画面用の語らい一覧レイアウト（2026-11-23追加）。
class TalksListLayoutStyleWideNotifier extends Notifier<TalksListLayoutStyle> {
  @override
  TalksListLayoutStyle build() =>
      ref.watch(initialTalksListLayoutStyleWideProvider);

  Future<void> setStyle(TalksListLayoutStyle style) async {
    state = style;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_wideKey, style.name);
  }
}

final talksListLayoutStyleWideProvider =
    NotifierProvider<TalksListLayoutStyleWideNotifier, TalksListLayoutStyle>(
      TalksListLayoutStyleWideNotifier.new,
    );
