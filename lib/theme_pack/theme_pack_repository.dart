import 'package:flutter/widgets.dart';

import 'theme_pack.dart';

/// 一覧に出す、意匠の要約。
@immutable
class ThemePackSummary {
  const ThemePackSummary({
    required this.id,
    required this.name,
    required this.author,
    this.owned = false,
    this.updateAvailable = false,
  });
  final String id;
  final String name;
  final String author;

  /// 横丁で取得した意匠か。
  final bool owned;

  /// 公開中の版が、取得した時の版より新しい。更新の案内だけに使う。
  final bool updateAvailable;
}

/// 意匠の置き場所を隠すインターフェース（自前化の方針、Repositoryパターン）。
/// 実装は、横丁で取得した意匠を読む`OwnedThemePackRepository`。
abstract class ThemePackRepository {
  /// 使える意匠の一覧。
  Future<List<ThemePackSummary>> list();

  /// [id]の意匠を読む。読めない時は[ThemePackException]を投げる。
  Future<ThemePack> load(String id);
}
