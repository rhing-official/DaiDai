import 'package:flutter/material.dart';

/// 住人のIDから決まる固定色と、Rhing Seedの頭文字だけで描く丸いアバター
/// （2026-10-10、管理画面の住人一覧用）。住人が設定したアイコンやカードの
/// 内容は一切使わない（運営が通常業務で個人の表現を眺めないため）。
/// 同じIDには常に同じ色が付くので、一覧の中で見分けやすくなる。
class GeneratedAvatar extends StatelessWidget {
  const GeneratedAvatar({
    required this.seed,
    required this.label,
    this.size = 40,
    super.key,
  });

  /// 色を決めるキー（`userId`）。
  final String seed;

  /// 頭文字に使う文字列（Rhing Seed）。空なら`?`。
  final String label;

  /// 直径。
  final double size;

  static const palette = [
    Color(0xFFEE7800),
    Color(0xFF6D4C41),
    Color(0xFF00897B),
    Color(0xFF5E35B1),
    Color(0xFF1E88E5),
    Color(0xFFD81B60),
  ];

  /// [seed]から決まる色。`String.hashCode`は実装によって値が変わりうるため、
  /// 安定したFNV-1aハッシュで選ぶ（同じIDは端末・実行をまたいで同じ色）。
  static Color colorFor(String seed) {
    var hash = 0x811c9dc5;
    for (final unit in seed.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return palette[hash % palette.length];
  }

  @override
  Widget build(BuildContext context) {
    final text = label.isEmpty ? '?' : label.characters.first.toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(shape: BoxShape.circle, color: colorFor(seed)),
      child: Text(
        text,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.42,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
