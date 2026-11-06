import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../app_theme_extras.dart';

/// 「ブロック」UI用のThemeDataを組み立てる（2026-11-06追加）。太い黒枠・ぼかしの無い
/// ずらした硬い影・アクセントの淡い面と濃いボタン（ネオブルータリズム風）。
/// フラットのテーマ（[AppTheme]）をベースに、色と形だけを上書きする。
///
/// - 色はアクセントカラーから導く。面は淡い色、ボタンはアクセントそのもの。文字は
///   黒（ダークは白）で、アクセントカラーにはしない。
/// - Materialの影（`elevation`）は使わず、硬い影は[BlockTheme.shadow]を`BoxShadow`で描く
///   （このスタイルだけの例外、CLAUDE.mdの「影を使わない」方針の例外）。
/// 「今のテーマがブロックか」を見分ける為の目印（[BlockTheme]だけが持つ）。
@immutable
class BlockThemeMarker extends ThemeExtension<BlockThemeMarker> {
  const BlockThemeMarker();

  @override
  BlockThemeMarker copyWith() => this;

  @override
  BlockThemeMarker lerp(ThemeExtension<BlockThemeMarker>? other, double t) =>
      this;
}

/// 現在のテーマがブロックか。
bool isBlockTheme(BuildContext context) =>
    Theme.of(context).extension<BlockThemeMarker>() != null;

/// 枠付きのカード（画像・動画・PDF・URL・予定・投票・ノートの通知など）の装飾。
/// フラット/ガラスは今まで通りアクセント色の細い枠。ブロックは黒の太枠と硬い影
/// （このスタイルだけの例外、影の置き場所の分だけ右・下へはみ出す）。
BoxDecoration framedCardDecoration(
  BuildContext context, {
  required BorderRadius borderRadius,
  Color? color,
}) {
  final theme = Theme.of(context);
  if (isBlockTheme(context)) {
    return BoxDecoration(
      color: color,
      border: Border.all(
        color: BlockTheme.lineColor(theme.brightness),
        width: BlockTheme.borderWidth,
      ),
      borderRadius: borderRadius,
      boxShadow: BlockTheme.shadow(theme.colorScheme.primary, theme.brightness),
    );
  }
  return BoxDecoration(
    color: color,
    border: Border.all(color: theme.colorScheme.primary),
    borderRadius: borderRadius,
  );
}

/// 既に塗りと角丸のクリップを持つウィジェット（URLプレビューカード等）に、ブロックの
/// 黒の太枠（前面）と硬い影（背面）を後付けする。ブロック以外では[child]をそのまま返す。
Widget blockCardWrap(
  BuildContext context, {
  required BorderRadius borderRadius,
  required Widget child,
}) {
  if (!isBlockTheme(context)) return child;
  final theme = Theme.of(context);
  return DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: borderRadius,
      boxShadow: BlockTheme.shadow(theme.colorScheme.primary, theme.brightness),
    ),
    child: DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        border: Border.all(
          color: BlockTheme.lineColor(theme.brightness),
          width: BlockTheme.borderWidth,
        ),
      ),
      child: child,
    ),
  );
}

/// 角丸の矩形に、黒の太枠と、ぼかしの無いずらした硬い影を描く形（ダイアログ・メニュー用、
/// `Material`の`shape`に渡す）。影は形の外側だけに描く（塗りの上には重ねない）。
/// ブロック以外のスタイルでは使わない（このスタイルだけの例外）。
class BlockShapeBorder extends OutlinedBorder {
  const BlockShapeBorder({
    required this.borderRadius,
    required this.lineColor,
    required this.shadowColor,
    this.shadowOffset = BlockTheme.shadowOffset,
    super.side = BorderSide.none,
  });

  final BorderRadius borderRadius;
  final Color lineColor;
  final Color shadowColor;
  final Offset shadowOffset;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(BlockTheme.borderWidth);

  @override
  OutlinedBorder copyWith({BorderSide? side}) => BlockShapeBorder(
    borderRadius: borderRadius,
    lineColor: lineColor,
    shadowColor: shadowColor,
    shadowOffset: shadowOffset,
    side: side ?? this.side,
  );

  @override
  ShapeBorder scale(double t) => this;

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      Path()
        ..addRRect(borderRadius.toRRect(rect).deflate(BlockTheme.borderWidth));

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      Path()..addRRect(borderRadius.toRRect(rect));

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    final rrect = borderRadius.toRRect(rect);
    canvas.save();
    canvas.clipPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(Rect.fromLTWH(-100000, -100000, 200000, 200000))
        ..addRRect(rrect),
    );
    canvas.drawRRect(rrect.shift(shadowOffset), Paint()..color = shadowColor);
    canvas.restore();
    canvas.drawRRect(
      rrect.deflate(BlockTheme.borderWidth / 2),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = BlockTheme.borderWidth
        ..color = lineColor,
    );
  }
}

class BlockTheme {
  BlockTheme._();

  /// 枠線の太さ。
  static const borderWidth = 2.5;

  /// 角丸。
  static const radius = 8.0;

  /// 硬い影のずらし量。
  static const shadowOffset = Offset(4, 4);

  /// ライトの枠・影の色（黒）／ダークの枠・影の色（明るい線）。
  static const lightLine = Colors.black;
  static const darkLine = Color(0xFFEDEDED);

  /// [accent]の色相を保ち、明度だけを[lightness]にした色（面の淡い色用）。
  static Color tint(
    Color accent,
    double lightness, {
    double maxSaturation = 1,
  }) {
    final hsl = HSLColor.fromColor(accent);
    return hsl
        .withLightness(lightness)
        .withSaturation(hsl.saturation.clamp(0.0, maxSaturation))
        .toColor();
  }

  /// 枠・影の色。
  static Color lineColor(Brightness brightness) =>
      brightness == Brightness.dark ? darkLine : lightLine;

  /// ぼかしの無い硬い影（ライトは黒、ダークはアクセント）。
  static List<BoxShadow> shadow(Color accent, Brightness brightness) => [
    BoxShadow(
      color: brightness == Brightness.dark ? accent : lightLine,
      offset: shadowOffset,
      blurRadius: 0,
    ),
  ];

  static ThemeData light(
    Color accentColor, {
    Color? textColor,
    Color? onAccentColor,
    String? fontFamily,
  }) => _build(
    AppTheme.light(
      accentColor,
      textColor: textColor,
      onAccentColor: onAccentColor,
      fontFamily: fontFamily,
    ),
    accentColor,
    Brightness.light,
  );

  static ThemeData dark(
    Color accentColor, {
    Color? textColor,
    Color? onAccentColor,
    String? fontFamily,
  }) => _build(
    AppTheme.dark(
      accentColor,
      textColor: textColor,
      onAccentColor: onAccentColor,
      fontFamily: fontFamily,
    ),
    accentColor,
    Brightness.dark,
  );

  static ThemeData _build(ThemeData base, Color accent, Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    // 透明度付きのアクセント（#RRGGBBAA）だと背景が透けて灰色っぽく見える為、
    // このスタイルでは常に不透明にする。
    accent = accent.withAlpha(0xFF);
    // ライト・ダークとも、設定のアクセントカラーをそのままprimary（チップ・ボタン・
    // トグルの塗り）に使う（2026-11-06、ライトだけ色を変えていたのを統一）。
    final line = lineColor(brightness);
    final side = BorderSide(color: line, width: borderWidth);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: side,
    );
    // 背景は淡い色、パネル（カード・ダイアログ・メニュー）はそれより少し濃い色。
    final background = isDark
        ? AppTheme.darkBackground
        : tint(accent, 0.975, maxSaturation: 0.8);
    final panel = isDark
        ? AppTheme.darkSurface
        : tint(accent, 0.945, maxSaturation: 0.8);
    final field = isDark ? AppTheme.darkSurface : tint(accent, 0.985);
    final scheme = base.colorScheme.copyWith(
      primary: accent,
      surface: background,
      surfaceContainerLowest: background,
      surfaceContainerLow: background,
      surfaceContainer: panel,
      surfaceContainerHigh: panel,
      surfaceContainerHighest: panel,
      outline: line,
      outlineVariant: line,
    );
    final onAccent = scheme.onPrimary;
    ButtonStyle filled({Size? minimumSize}) => ButtonStyle(
      backgroundColor: WidgetStatePropertyAll(accent),
      foregroundColor: WidgetStatePropertyAll(onAccent),
      elevation: const WidgetStatePropertyAll(0),
      minimumSize: WidgetStatePropertyAll(minimumSize ?? const Size(0, 48)),
      shape: WidgetStatePropertyAll(shape),
    );
    final extras = base.extension<AppThemeExtras>();
    return base.copyWith(
      scaffoldBackgroundColor: background,
      colorScheme: scheme,
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: background,
        shape: Border(bottom: side),
      ),
      // カード・チップ・スナックバーも、ダイアログと同じ「太枠＋硬い影」の形にする
      // （テーマで一括。形の外側にだけ影を描く、このスタイルだけの例外）。
      cardTheme: CardThemeData(
        color: panel,
        elevation: 0,
        margin: const EdgeInsets.fromLTRB(4, 4, 8, 8),
        shape: BlockShapeBorder(
          borderRadius: BorderRadius.circular(radius),
          lineColor: line,
          shadowColor: isDark ? accent : line,
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: isDark ? AppTheme.darkSurface : Colors.white,
        selectedColor: accent,
        disabledColor: panel,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        pressElevation: 0,
        side: BorderSide.none,
        labelStyle: TextStyle(color: scheme.onSurface),
        checkmarkColor: onAccent,
        shape: BlockShapeBorder(
          borderRadius: BorderRadius.circular(radius),
          lineColor: line,
          shadowColor: isDark ? accent : line,
          shadowOffset: const Offset(3, 3),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: panel,
        contentTextStyle: TextStyle(color: scheme.onSurface),
        actionTextColor: scheme.onSurface,
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: BlockShapeBorder(
          borderRadius: BorderRadius.circular(radius),
          lineColor: line,
          shadowColor: isDark ? accent : line,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: filled(minimumSize: const Size.fromHeight(52)),
      ),
      filledButtonTheme: FilledButtonThemeData(style: filled()),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.onSurface,
          side: side,
          shape: shape,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: accent,
        foregroundColor: onAccent,
        elevation: 0,
        highlightElevation: 0,
        shape: shape,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: panel,
        elevation: 0,
        constraints: const BoxConstraints(maxWidth: 400),
        // 太枠＋硬い影（ブロックだけの例外）。形の外側にだけ影を描く。
        shape: BlockShapeBorder(
          borderRadius: BorderRadius.circular(12),
          lineColor: line,
          shadowColor: isDark ? accent : line,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: panel,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          side: side,
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: panel,
        elevation: 0,
        shape: BlockShapeBorder(
          borderRadius: BorderRadius.circular(radius),
          lineColor: line,
          shadowColor: isDark ? accent : line,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: field,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: side,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: side,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: side.copyWith(width: borderWidth + 1),
        ),
      ),
      extensions: [
        const BlockThemeMarker(),
        AppThemeExtras(
          floatingShadow: shadow(accent, brightness),
          textTertiary: extras?.textTertiary ?? scheme.onSurfaceVariant,
        ),
      ],
    );
  }
}

/// 版画の「枠付きの面」（チップ・ピル・ボタン状の箱）。黒の太枠と硬い影（影は右・下へ
/// [shadowOffset]だけはみ出す）。中身のタップは`InkWell`でそのまま使える（面が`Material`）。
/// 版画以外では使わない（呼び出し側で[isBlockTheme]等を見て分岐する）。
Widget blockMaterialBox(
  BuildContext context, {
  required Widget child,
  Color? color,
  double radius = BlockTheme.radius,
  Offset shadowOffset = const Offset(3, 3),
}) {
  final theme = Theme.of(context);
  final line = BlockTheme.lineColor(theme.brightness);
  final shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(radius),
    side: BorderSide(color: line, width: BlockTheme.borderWidth),
  );
  return DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      boxShadow: [
        BoxShadow(
          color: theme.brightness == Brightness.dark
              ? theme.colorScheme.primary
              : line,
          offset: shadowOffset,
          blurRadius: 0,
        ),
      ],
    ),
    child: Material(
      color: color ?? theme.colorScheme.surface,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: child,
    ),
  );
}

/// 版画のアイコンボタン（太枠と硬い影の正方形）。[filled]ならアクセントで塗る。
/// [onPressed]がnullなら見た目だけ（親の`Listener`等がタップを受ける場合）。
Widget blockIconButton(
  BuildContext context, {
  required IconData icon,
  VoidCallback? onPressed,
  double size = 36,
  bool filled = false,
}) {
  final scheme = Theme.of(context).colorScheme;
  final light = Theme.of(context).brightness == Brightness.light;
  return Padding(
    padding: const EdgeInsets.only(right: 3, bottom: 3),
    child: blockMaterialBox(
      context,
      color: filled ? scheme.primary : (light ? Colors.white : scheme.surface),
      child: InkWell(
        onTap: onPressed,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(
            icon,
            size: size * 0.55,
            color: filled ? scheme.onPrimary : scheme.onSurface,
          ),
        ),
      ),
    ),
  );
}

/// ヘッダーのボタン（`IconButton`の`icon`に入れる）用の、版画のアイコンバッジ。
/// 太枠と硬い影の小さな箱にアイコンを載せる。タップは外側の`IconButton`が受ける。
class BlockIconBadge extends StatelessWidget {
  const BlockIconBadge({required this.icon, this.size = 32, super.key});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return blockMaterialBox(
      context,
      color: Theme.of(context).brightness == Brightness.light
          ? Colors.white
          : scheme.surface,
      shadowOffset: const Offset(2, 2),
      child: SizedBox(
        width: size,
        height: size,
        child: Icon(icon, size: size * 0.6, color: scheme.onSurface),
      ),
    );
  }
}

/// 入力欄を、版画だけ太枠と硬い影の箱で囲む（他のスタイルでは[child]をそのまま返す）。
/// 中の`TextField`は枠・塗り無し（[isBlockTheme]で`InputBorder.none`等にする）。
///
/// 枠が入力欄の外側にある為、`TextField`の浮くラベル（`labelText`）は枠線に被って
/// しまう。そこで版画では`labelText`を使わず、[label]を箱の上に別の文字として置く。
class BlockFieldFrame extends StatelessWidget {
  const BlockFieldFrame({required this.child, this.label, super.key});

  final Widget child;

  /// 箱の上に出すラベル（版画の時だけ。他のスタイルでは`TextField`側のラベルを使う）。
  final String? label;

  @override
  Widget build(BuildContext context) {
    if (!isBlockTheme(context)) return child;
    final theme = Theme.of(context);
    final box = Padding(
      padding: const EdgeInsets.only(right: 4, bottom: 4),
      child: blockMaterialBox(
        context,
        color: theme.brightness == Brightness.light
            ? Colors.white
            : theme.colorScheme.surface,
        child: child,
      ),
    );
    final label = this.label;
    if (label == null) return box;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 6),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ),
        box,
      ],
    );
  }
}

/// 版画の箱を、中の文字の幅に合わせて左寄せにする（劇画の箱と同じ内容幅）。
/// 親の最大幅が上限で、長い題名はそこで折り返す。[alignEnd]なら右寄せ。
/// `ListTile`の固有幅は余白（文字とアイコンの間隔）を数えず短めに出る為、
/// その分の余裕[_fitSlack]を足して、文字が不要に折り返さないようにする。
Widget blockFitWidth(Widget box, {bool alignEnd = false}) {
  return Align(
    alignment: alignEnd ? Alignment.centerRight : Alignment.centerLeft,
    child: _BlockFitWidth(child: box),
  );
}

const double _fitSlack = 32;

class _BlockFitWidth extends SingleChildRenderObjectWidget {
  const _BlockFitWidth({super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderBlockFitWidth();
}

class _RenderBlockFitWidth extends RenderShiftedBox {
  _RenderBlockFitWidth() : super(null);

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.smallest;
      return;
    }
    final wanted = child.getMaxIntrinsicWidth(double.infinity) + _fitSlack;
    final width = wanted.clamp(constraints.minWidth, constraints.maxWidth);
    child.layout(
      BoxConstraints(
        minWidth: width,
        maxWidth: width,
        maxHeight: constraints.maxHeight,
      ),
      parentUsesSize: true,
    );
    size = constraints.constrain(child.size);
  }

  @override
  double computeMinIntrinsicWidth(double height) =>
      (child?.getMaxIntrinsicWidth(height) ?? 0) + _fitSlack;

  @override
  double computeMaxIntrinsicWidth(double height) =>
      (child?.getMaxIntrinsicWidth(height) ?? 0) + _fitSlack;
}
