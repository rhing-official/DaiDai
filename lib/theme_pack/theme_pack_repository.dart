import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'theme_pack.dart';

/// 一覧に出す、パックの要約。
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

  /// 横丁で取得した意匠か（同梱の公式パックはfalse）。
  final bool owned;

  /// 公開中の版が、取得した時の版より新しい。更新の案内だけに使う。
  final bool updateAvailable;
}

/// 素材パックの置き場所を隠すインターフェース（自前化の方針、Repositoryパターン）。
/// 今は同梱の公式パックだけ。投稿されたパックを横丁のストレージから取る実装は、
/// 横丁側の投稿・審査の仕組みが出来てから足す。
abstract class ThemePackRepository {
  /// 使えるパックの一覧。
  Future<List<ThemePackSummary>> list();

  /// [id]のパックを読む。読めない時は[ThemePackException]を投げる。
  Future<ThemePack> load(String id);
}

/// アプリに同梱した公式パック（`assets/theme_packs/`）。
/// `index.json`に`{"packs": ["sakura", ...]}`を書き、各パックは`<id>/pack.json`と画像を持つ。
class BundledThemePackRepository implements ThemePackRepository {
  BundledThemePackRepository({
    AssetBundle? bundle,
    this.root = 'assets/theme_packs',
  }) : _bundle = bundle ?? rootBundle;

  final AssetBundle _bundle;
  final String root;

  @override
  Future<List<ThemePackSummary>> list() async {
    final List<String> ids;
    try {
      final index =
          jsonDecode(await _bundle.loadString('$root/index.json'))
              as Map<String, dynamic>;
      ids = [for (final v in (index['packs'] as List)) v as String];
    } catch (_) {
      return const [];
    }
    final out = <ThemePackSummary>[];
    for (final id in ids) {
      try {
        final pack = (await _read(id)).pack;
        out.add(
          ThemePackSummary(id: pack.id, name: pack.name, author: pack.author),
        );
      } on ThemePackException {
        // 読めないパックは一覧に出さない。
      }
    }
    return out;
  }

  @override
  Future<ThemePack> load(String id) async {
    final parsed = await _read(id);
    final file = parsed.backgroundImageFile;
    if (file == null) return parsed.pack;
    final path = '$root/$id/$file';
    try {
      await _bundle.load(path);
    } catch (_) {
      throw const ThemePackException('背景画像が見つかりません');
    }
    return parsed.pack.withBackgroundImage(AssetImage(path));
  }

  Future<ParsedThemePack> _read(String id) async {
    if (!RegExp(r'^[a-z0-9\-]{1,40}$').hasMatch(id)) {
      throw const ThemePackException('idが正しくありません');
    }
    final String source;
    try {
      source = await _bundle.loadString('$root/$id/pack.json');
    } catch (_) {
      throw const ThemePackException('パックが見つかりません');
    }
    final parsed = ThemePackParser.parse(source);
    if (parsed.pack.id != id) {
      throw const ThemePackException('idがフォルダ名と合いません');
    }
    return parsed;
  }
}
