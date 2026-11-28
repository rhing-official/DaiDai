import 'package:flutter/material.dart';

/// daidai横丁（Web、HomePage）の色。横丁の見た目をそのまま写すため、アプリのテーマ・
/// アクセントカラーに従わず、横丁の`globals.css`の値を固定で持つ（2026-11-28、ユーザー指示）。
/// ライトとダークの別は、アプリの明るさに合わせる。
class YokochoPalette {
  const YokochoPalette._({
    required this.surface,
    required this.card,
    required this.containerHigh,
    required this.onSurface,
    required this.onSurfaceVariant,
    required this.subtle,
    required this.outline,
    required this.outlineVariant,
    required this.glassEdge,
    required this.primary,
    required this.onPrimary,
    required this.primaryContainer,
    required this.onPrimaryContainer,
    required this.free,
    required this.paid,
  });

  final Color surface;
  final Color card;
  final Color containerHigh;
  final Color onSurface;
  final Color onSurfaceVariant;
  final Color subtle;
  final Color outline;
  final Color outlineVariant;
  final Color glassEdge;
  final Color primary;
  final Color onPrimary;
  final Color primaryContainer;
  final Color onPrimaryContainer;
  final Color free;
  final Color paid;

  static const light = YokochoPalette._(
    surface: Color(0xFFFCFBF7),
    card: Color(0xFFFFFFFF),
    containerHigh: Color(0xFFF3F4F6),
    onSurface: Color(0xFF111827),
    onSurfaceVariant: Color(0xFF4B5563),
    subtle: Color(0xFF6B7280),
    outline: Color(0xFF9CA3AF),
    outlineVariant: Color(0xFFE5E7EB),
    glassEdge: Color(0xFFFFFFFF),
    primary: Color(0xFF2563EB),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFDBEAFE),
    onPrimaryContainer: Color(0xFF1E3A8A),
    free: Color(0xFF059669),
    paid: Color(0xFFD97706),
  );

  static const dark = YokochoPalette._(
    surface: Color(0xFF171613),
    card: Color(0xFF201F1B),
    containerHigh: Color(0xFF292822),
    onSurface: Color(0xFFECEBE6),
    onSurfaceVariant: Color(0xFFB9B7AE),
    subtle: Color(0xFFA3A198),
    outline: Color(0xFF8A877D),
    outlineVariant: Color(0xFF3B3933),
    glassEdge: Color(0xFF4A483F),
    primary: Color(0xFF93C5FD),
    onPrimary: Color(0xFF0B2545),
    primaryContainer: Color(0xFF1E3A8A),
    onPrimaryContainer: Color(0xFFDBEAFE),
    free: Color(0xFF34D399),
    paid: Color(0xFFFBBF24),
  );

  static YokochoPalette of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;
}
