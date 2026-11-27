import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/dark_variant.dart';
import '../../widgets/kinari_surface.dart';
import '../app_theme.dart';

/// 「生成り」スタイルの固定色（2026-11-26）。生成りの紙に、濃紺の線・文字。
class KinariColors {
  KinariColors._();

  /// 紙（背景）。
  static const paper = Color(0xFFEFE9DD);

  /// 紙より少し濃い面（カード・ダイアログ）。
  static const surface = Color(0xFFE6DFD0);

  /// 濃紺（線・文字・アイコン）。
  static const ink = Color(0xFF1F2A5A);
}

/// 現在のテーマが生成りか（部品の出し分け用、2026-11-27）。
class KinariThemeMarker extends ThemeExtension<KinariThemeMarker> {
  const KinariThemeMarker();

  @override
  KinariThemeMarker copyWith() => this;

  @override
  KinariThemeMarker lerp(ThemeExtension<KinariThemeMarker>? other, double t) =>
      this;
}

bool isKinariTheme(BuildContext context) =>
    Theme.of(context).extension<KinariThemeMarker>() != null;

/// 生成りスタイルのThemeData。ライト/ダークによらず、紙の色に固定する。
class KinariTheme {
  KinariTheme._();

  /// 背景に応じた線・文字の色。暗い背景では、明るい色にする。
  static Color inkFor(Color background) =>
      ThemeData.estimateBrightnessForColor(background) == Brightness.dark
      ? const Color(0xFFEDE8DC)
      : KinariColors.ink;

  /// [background]を渡すと、紙の代わりに、その色の背景で描く（設定>背景）。
  static ThemeData build(
    Color accentColor,
    String? fontFamily, {
    Color? background,
    Color? onAccentColor,
  }) {
    final palette = background == null
        ? const AppearancePalette(
            background: KinariColors.paper,
            surface: KinariColors.surface,
            glassBackground: KinariColors.paper,
            glassSurface: KinariColors.surface,
          )
        : AppearancePalette.fromBackground(background);
    final ink = inkFor(palette.background);
    final dark = ink != KinariColors.ink;
    final base = dark
        ? AppTheme.dark(
            accentColor,
            textColor: ink,
            onAccentColor: onAccentColor,
            fontFamily: fontFamily,
            palette: palette,
          )
        : AppTheme.light(
            accentColor,
            textColor: ink,
            onAccentColor: onAccentColor,
            fontFamily: fontFamily,
            palette: palette,
          );
    // 面の縁は、濃紺の細い線（1px、少し透かす）。影は使わない。
    RoundedRectangleBorder shape(double radius) => RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: BorderSide(color: ink.withValues(alpha: 0.4)),
    );
    OutlineInputBorder field(Color color, double width) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: color, width: width),
    );
    // ポップアップは、へこんだ面（少し濃い紙色に、内側の影）。
    final popupColor = Color.lerp(palette.surface, Colors.black, 0.04);
    KinariInsetBorder insetShape(double radius) => KinariInsetBorder(
      borderRadius: BorderRadius.circular(radius),
      side: BorderSide(color: ink.withValues(alpha: 0.4)),
    );
    // 浮く部品（ボタン・カード）は、柔らかい影でわずかに浮かせる。
    final lift = ink.withValues(alpha: 0.4);
    final onAccent =
        onAccentColor ??
        (ThemeData.estimateBrightnessForColor(accentColor) == Brightness.dark
            ? Colors.white
            : Colors.black);
    return base.copyWith(
      extensions: [...base.extensions.values, const KinariThemeMarker()],
      cardTheme: CardThemeData(
        color: palette.surface,
        elevation: 2,
        shadowColor: lift,
        surfaceTintColor: Colors.transparent,
        shape: shape(16),
      ),
      dialogTheme: DialogThemeData(
        constraints: const BoxConstraints(maxWidth: 400),
        backgroundColor: popupColor,
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        shape: insetShape(24),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accentColor,
          foregroundColor: onAccent,
          elevation: 3,
          shadowColor: lift,
          surfaceTintColor: Colors.transparent,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accentColor,
          foregroundColor: onAccent,
          elevation: 3,
          shadowColor: lift,
          surfaceTintColor: Colors.transparent,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: accentColor,
        foregroundColor: onAccent,
        elevation: 3,
        highlightElevation: 5,
        shape: const CircleBorder(),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: popupColor,
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        shape: insetShape(12),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: popupColor,
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        shape: KinariInsetBorder(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          side: BorderSide(color: ink.withValues(alpha: 0.4)),
        ),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(popupColor),
          elevation: const WidgetStatePropertyAll(0),
          shape: WidgetStatePropertyAll(insetShape(12)),
        ),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(popupColor),
          elevation: const WidgetStatePropertyAll(0),
          shape: WidgetStatePropertyAll(insetShape(12)),
        ),
      ),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        // へこんだ面（紙より濃い色）に、細い縁。
        filled: true,
        fillColor: Color.lerp(palette.surface, Colors.black, 0.06),
        border: field(ink.withValues(alpha: 0.25), 1),
        enabledBorder: field(ink.withValues(alpha: 0.25), 1),
        focusedBorder: field(ink.withValues(alpha: 0.8), 1.4),
      ),
      dividerTheme: DividerThemeData(
        color: ink.withValues(alpha: 0.18),
        thickness: 1,
        space: 1,
      ),
    );
  }
}

/// 紙に混ざった繊維を、ごく薄く画面全体へ重ねる層（タッチは通さない）。大きさが変わる時だけ描き直す。
class KinariPaperFibers extends StatelessWidget {
  const KinariPaperFibers({required this.color, super.key});

  final Color color;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: RepaintBoundary(
      child: CustomPaint(painter: _FiberPainter(color), size: Size.infinite),
    ),
  );
}

class _FiberPainter extends CustomPainter {
  _FiberPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final random = math.Random(11);
    final count = (size.width * size.height / 2600).clamp(150, 1800).toInt();
    final path = Path();
    for (var i = 0; i < count; i++) {
      final x = random.nextDouble() * size.width;
      final y = random.nextDouble() * size.height;
      final angle = random.nextDouble() * math.pi;
      final length = 5 + random.nextDouble() * 12;
      final bend = (random.nextDouble() - 0.5) * 6;
      path
        ..moveTo(x, y)
        ..quadraticBezierTo(
          x + math.cos(angle) * length / 2 + bend,
          y + math.sin(angle) * length / 2 + bend,
          x + math.cos(angle) * length,
          y + math.sin(angle) * length,
        );
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.7
        ..strokeCap = StrokeCap.round
        ..color = color.withValues(alpha: 0.07),
    );
  }

  @override
  bool shouldRepaint(covariant _FiberPainter old) => old.color != color;
}
