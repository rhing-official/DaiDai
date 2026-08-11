import 'package:flutter/widgets.dart';

/// アプリ全体で使う「ポップ」演出（フェード＋下からのわずかなスライド＋
/// わずかな拡大）の共通パラメータ。元々`PopSlidePageTransitionsBuilder`
/// （`app_theme.dart`）のフルスクリーン画面遷移専用だったものを、設定/
/// 身だしなみのドリルダウン（`settings_tab.dart`/`profile_tab.dart`の
/// `AnimatedSwitcher`）でも同じモーション言語になるよう共通化した
/// （2026-08-10追加）。
const popSlideDuration = Duration(milliseconds: 220);
const popSlideCurve = Curves.easeOutCubic;
const popSlideBeginOffset = Offset(0, 0.06);
const popSlideBeginScale = 0.97;

/// [popSlideDuration]で0→1に進む[animation]から、ポップ演出でラップした
/// [child]を作る。フルスクリーン遷移・ドリルダウンでこの関数を共有する。
Widget buildPopSlideTransition(Animation<double> animation, Widget child) {
  final curved = CurvedAnimation(parent: animation, curve: popSlideCurve);
  return FadeTransition(
    opacity: curved,
    child: SlideTransition(
      position: Tween<Offset>(
        begin: popSlideBeginOffset,
        end: Offset.zero,
      ).animate(curved),
      child: ScaleTransition(
        scale: Tween<double>(begin: popSlideBeginScale, end: 1).animate(curved),
        child: child,
      ),
    ),
  );
}
