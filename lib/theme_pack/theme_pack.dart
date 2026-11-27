import 'dart:convert';

import 'package:flutter/material.dart';

import '../models/dark_variant.dart';
import '../theme/block/block_tokens.dart';
import '../utils/color_hex.dart';

/// 意匠の形式の版。アプリが読めるのはこの版以下（2026-11-26、`文書/検討/素材パック.md`）。
const int kThemePackFormatVersion = 1;

/// 意匠が対応する明るさ。片方だけなら、端末の設定に関わらずその明るさで表示する。
enum ThemePackBrightness {
  light,
  dark,
  both;

  static ThemePackBrightness? fromName(String? name) {
    for (final v in values) {
      if (v.name == name) return v;
    }
    return null;
  }
}

/// 1つの明るさ向けの色。未指定（null）の色は、版画の標準の導き方に任せる。
@immutable
class ThemePackColors {
  const ThemePackColors({
    this.accent,
    this.background,
    this.panel,
    this.text,
    this.onAccent,
    this.line,
  });

  final Color? accent;
  final Color? background;
  final Color? panel;
  final Color? text;
  final Color? onAccent;
  final Color? line;
}

/// 読み込んだ意匠。コードは含まず、決まった項目だけを持つ。
@immutable
class ThemePack {
  const ThemePack({
    required this.id,
    required this.name,
    required this.author,
    required this.brightness,
    required this.tokens,
    required this.light,
    required this.dark,
    this.backgroundImage,
    this.menuChipImage,
  });

  final String id;
  final String name;
  final String author;
  final ThemePackBrightness brightness;

  /// 枠の太さ・角丸・影のずれ・枠の色（ライトとダーク）。
  final BlockTokens tokens;

  final ThemePackColors light;
  final ThemePackColors dark;

  /// 背景画像。意匠を置いた場所に応じて、読み込み側が解決する。
  final ImageProvider? backgroundImage;

  /// メニューチップの丸い面に敷く画像（2026-11-27）。無ければ版画の標準の面。
  final ImageProvider? menuChipImage;

  ThemePackColors colorsFor(Brightness b) =>
      b == Brightness.dark ? dark : light;

  /// 背景（と面）の色を指定した意匠だけ、面の色の組を返す。無ければnull（版画の標準の導き方）。
  AppearancePalette? paletteFor(Brightness b) {
    final c = colorsFor(b);
    final bg = c.background;
    if (bg == null) return null;
    // 利用者が指定する背景色と同じ関数に通す。意匠は背景色とパネルの色だけを渡し、他の色は
    // 同じ関数が作る（2026-11-27）。
    return AppearancePalette.fromBackground(bg, surface: c.panel);
  }

  /// この明るさで表示するか。両対応なら端末の設定に従う（null）。
  ThemeMode? get forcedThemeMode => switch (brightness) {
    ThemePackBrightness.light => ThemeMode.light,
    ThemePackBrightness.dark => ThemeMode.dark,
    ThemePackBrightness.both => null,
  };

  /// 取得済みの意匠は、一覧と選択中の照合に、投稿者を含む識別子を使う。
  ThemePack withId(String newId) => ThemePack(
    id: newId,
    name: name,
    author: author,
    brightness: brightness,
    tokens: tokens,
    light: light,
    dark: dark,
    backgroundImage: backgroundImage,
    menuChipImage: menuChipImage,
  );

  ThemePack withBackgroundImage(ImageProvider? image) => ThemePack(
    id: id,
    name: name,
    author: author,
    brightness: brightness,
    tokens: tokens,
    light: light,
    dark: dark,
    backgroundImage: image,
    menuChipImage: menuChipImage,
  );

  ThemePack withMenuChipImage(ImageProvider? image) => ThemePack(
    id: id,
    name: name,
    author: author,
    brightness: brightness,
    tokens: tokens,
    light: light,
    dark: dark,
    backgroundImage: backgroundImage,
    menuChipImage: image,
  );
}

/// 設定ファイルを読めなかった理由。設定画面に1行で出す。
class ThemePackException implements Exception {
  const ThemePackException(this.reason);
  final String reason;
  @override
  String toString() => 'ThemePackException: $reason';
}

/// 設定ファイル（JSON）の画像の相対パス。`..`・絶対パス・URLは受け付けない
/// （意匠の外のファイルを読ませない）。
final RegExp _safeImagePath = RegExp(r'^[A-Za-z0-9_\-]+(\.[A-Za-z0-9]+)?$');

class ThemePackParser {
  const ThemePackParser._();

  static const double maxBorderWidth = 6;
  static const double maxRadius = 32;
  static const double maxShadowOffset = 12;

  /// 設定ファイルの文字列から[ThemePack]を作る。壊れている・版が新しい・必須項目が無い場合は
  /// [ThemePackException]を投げる。範囲外の数値は、範囲へ丸める。
  /// 画像は、ファイル名だけを返す（[ParsedThemePack.backgroundImageFile]）。
  static ParsedThemePack parse(String source) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException {
      throw const ThemePackException('設定ファイルが壊れています');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const ThemePackException('設定ファイルの形が正しくありません');
    }
    final version = decoded['formatVersion'];
    if (version is! int) {
      throw const ThemePackException('形式の版が書かれていません');
    }
    if (version > kThemePackFormatVersion) {
      throw const ThemePackException('このアプリより新しい形式の意匠です');
    }
    final id = decoded['id'];
    final name = decoded['name'];
    if (id is! String || !RegExp(r'^[a-z0-9\-]{1,40}$').hasMatch(id)) {
      throw const ThemePackException('idが正しくありません');
    }
    if (name is! String || name.trim().isEmpty || name.length > 40) {
      throw const ThemePackException('名前が正しくありません');
    }
    final author = decoded['author'];
    final brightness =
        ThemePackBrightness.fromName(decoded['brightness'] as String?) ??
        ThemePackBrightness.both;

    final shape = _map(decoded['shape']);
    final colors = _map(decoded['colors']);
    final lightColors = _colors(_map(colors['light']));
    final darkColors = _colors(_map(colors['dark']));

    final offset = shape['shadowOffset'];
    var shadow = const Offset(4, 4);
    if (offset is List &&
        offset.length == 2 &&
        offset[0] is num &&
        offset[1] is num) {
      shadow = Offset(
        _clamp(
          (offset[0] as num).toDouble(),
          -maxShadowOffset,
          maxShadowOffset,
        ),
        _clamp(
          (offset[1] as num).toDouble(),
          -maxShadowOffset,
          maxShadowOffset,
        ),
      );
    }
    final tokens = BlockTokens(
      borderWidth: _clamp(
        (shape['borderWidth'] as num?)?.toDouble() ?? 2.5,
        0,
        maxBorderWidth,
      ),
      radius: _clamp((shape['radius'] as num?)?.toDouble() ?? 8, 0, maxRadius),
      shadowOffset: shadow,
      lightLine: lightColors.line ?? Colors.black,
      darkLine: darkColors.line ?? const Color(0xFFEDEDED),
    );

    String? imageFile;
    final images = _map(decoded['images']);
    final bg = images['background'];
    if (bg != null) {
      if (bg is! String || !_safeImagePath.hasMatch(bg)) {
        throw const ThemePackException('背景画像のファイル名が正しくありません');
      }
      imageFile = bg;
    }
    String? menuChipFile;
    final chip = images['menuChip'];
    if (chip != null) {
      if (chip is! String || !_safeImagePath.hasMatch(chip)) {
        throw const ThemePackException('メニューチップ画像のファイル名が正しくありません');
      }
      menuChipFile = chip;
    }

    return ParsedThemePack(
      pack: ThemePack(
        id: id,
        name: name.trim(),
        author: author is String ? author : '',
        brightness: brightness,
        tokens: tokens,
        light: lightColors,
        dark: darkColors,
      ),
      backgroundImageFile: imageFile,
      menuChipImageFile: menuChipFile,
    );
  }

  static Map<String, dynamic> _map(Object? v) =>
      v is Map<String, dynamic> ? v : const <String, dynamic>{};

  static ThemePackColors _colors(Map<String, dynamic> m) => ThemePackColors(
    accent: _color(m['accent']),
    background: _color(m['background']),
    panel: _color(m['panel']),
    text: _color(m['text']),
    onAccent: _color(m['onAccent']),
    line: _color(m['line']),
  );

  /// `#RRGGBB`の色。透明度は無視して不透明にする。読めない色は、未指定として扱う。
  static Color? _color(Object? v) {
    if (v is! String) return null;
    return tryParseHexColor(v)?.withAlpha(0xFF);
  }

  static double _clamp(double v, double min, double max) =>
      v.isNaN ? min : v.clamp(min, max).toDouble();
}

/// 設定ファイルの読み取り結果。画像は、置き場所の側が解決する。
class ParsedThemePack {
  const ParsedThemePack({
    required this.pack,
    this.backgroundImageFile,
    this.menuChipImageFile,
  });
  final ThemePack pack;
  final String? backgroundImageFile;
  final String? menuChipImageFile;
}
