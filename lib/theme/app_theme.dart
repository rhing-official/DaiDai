import 'package:flutter/material.dart';

import '../models/ui_style.dart';
import 'app_theme_extras.dart';

/// UIスタイルごとのThemeDataを組み立てる。
class AppTheme {
  AppTheme._();

  static ThemeData themeFor(UiStyle style) {
    switch (style) {
      case UiStyle.daidai:
        return _daidaiTheme;
      case UiStyle.simple:
        return _simpleTheme;
    }
  }

  static final _daidaiColorScheme =
      ColorScheme.fromSeed(seedColor: const Color(0xFFEE7800));

  static final _daidaiTheme = ThemeData(
    colorScheme: _daidaiColorScheme,
    useMaterial3: true,
    navigationBarTheme: NavigationBarThemeData(
      indicatorColor: _daidaiColorScheme.primary.withValues(alpha: 0.2),
    ),
    navigationRailTheme: NavigationRailThemeData(
      indicatorColor: _daidaiColorScheme.primary.withValues(alpha: 0.2),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: _daidaiColorScheme.primary,
      foregroundColor: Colors.white,
    ),
    extensions: const [AppThemeExtras(floatingShadow: AppThemeExtras.none)],
  );

  // 「one year」（mobbin参考）のシンプルUIを参考にした配色・フォント・余白設計。
  // ラベンダー系の背景に紫がかった藍色をアクセントとして使い、
  // 装飾を減らして余白を広く取る。手書きイラストなどの独自アイコン素材は導入しない。
  // ボタン・カードは強めのelevationとアクセント色の影で「浮いている」印象を出し、
  // 画面遷移・ポップアップにはスライド＋ポップのアニメーションを付ける。
  static const _simpleBackground = Color(0xFFE7E5EF);
  static const _simpleSurface = Color(0xFFDAD8E8);
  static const _simpleAccent = Color(0xFF3D2EE0);
  static const _simpleText = Color(0xFF201F2B);

  static final _simpleFloatingShadow = [
    BoxShadow(
      color: _simpleAccent.withValues(alpha: 0.22),
      blurRadius: 24,
      offset: const Offset(0, 10),
    ),
  ];

  static final _simpleTheme = ThemeData(
    useMaterial3: true,
    fontFamily: 'monospace',
    scaffoldBackgroundColor: _simpleBackground,
    colorScheme: ColorScheme.fromSeed(
      seedColor: _simpleAccent,
      brightness: Brightness.light,
      surface: _simpleSurface,
    ).copyWith(primary: _simpleAccent, onPrimary: Colors.white),
    visualDensity: VisualDensity.comfortable,
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: _PopSlidePageTransitionsBuilder(),
        TargetPlatform.iOS: _PopSlidePageTransitionsBuilder(),
        TargetPlatform.macOS: _PopSlidePageTransitionsBuilder(),
        TargetPlatform.windows: _PopSlidePageTransitionsBuilder(),
        TargetPlatform.linux: _PopSlidePageTransitionsBuilder(),
      },
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: _simpleBackground,
      foregroundColor: _simpleText,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: _simpleSurface,
      elevation: 6,
      shadowColor: _simpleAccent.withValues(alpha: 0.3),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(20)),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: _simpleAccent,
        foregroundColor: Colors.white,
        elevation: 10,
        shadowColor: _simpleAccent.withValues(alpha: 0.5),
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ).copyWith(
        // 押した瞬間はぺたっと沈む＝浮いていた分の影が消えるように見せる。
        elevation: const WidgetStatePropertyAll(10),
        overlayColor: WidgetStatePropertyAll(
          Colors.white.withValues(alpha: 0.12),
        ),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: _simpleAccent,
      foregroundColor: Colors.white,
      elevation: 10,
      highlightElevation: 14,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: _simpleSurface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: _simpleBackground,
      elevation: 8,
      shadowColor: _simpleAccent.withValues(alpha: 0.3),
      indicatorColor: _simpleAccent.withValues(alpha: 0.2),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: _simpleBackground,
      indicatorColor: _simpleAccent.withValues(alpha: 0.2),
    ),
    textTheme: ThemeData.light().textTheme.apply(
          fontFamily: 'monospace',
          bodyColor: _simpleText,
          displayColor: _simpleText,
        ),
    extensions: [AppThemeExtras(floatingShadow: _simpleFloatingShadow)],
  );
}

/// シンプルUI用の画面遷移: 少し下から浮き上がりながらフェードイン＋
/// わずかに拡大する「ポップ」演出。
class _PopSlidePageTransitionsBuilder extends PageTransitionsBuilder {
  const _PopSlidePageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.06),
          end: Offset.zero,
        ).animate(curved),
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.97, end: 1).animate(curved),
          child: child,
        ),
      ),
    );
  }
}
