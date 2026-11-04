import 'dart:ui' show ImageFilter;

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

/// 画面右外から`Offset.zero`へ平行移動する入場演出（拡大は付けない、2026-09-11追加。
/// 2026-11-02にスライドと同時のフェード（薄い→濃い）を追加）。`InteractiveSwipeBackTransition`が右スワイプで
/// 戻る時に行う`Transform.translate`（画面を右へ動かして背後を見せる）の
/// 逆再生に相当する見え方にすることで、寄合一覧を左スワイプ/タップで開いた
/// 時の入場アニメーションと、右スワイプで戻る動きを対称にする（`talks_tab.dart`
/// の`openRoomFullscreen`参照）。
Widget buildSlideInFromRightTransition(
  Animation<double> animation,
  Widget child,
) {
  final curved = CurvedAnimation(parent: animation, curve: popSlideCurve);
  // スライドに合わせて薄い状態から濃くなる（戻る時は逆再生で薄くなる）、2026-11-02。
  return FadeTransition(
    opacity: curved,
    child: SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(1, 0),
        end: Offset.zero,
      ).animate(curved),
      // 離れているほど滲ませる（2026-11-04）。
      child: AnimatedBuilder(
        animation: curved,
        child: child,
        builder: (context, child) =>
            buildTransitionBlur(1 - curved.value, child!),
      ),
    ),
  );
}

/// 画面遷移で、重なるページが離れるほど（[amount]が1に近いほど）滲むぼかしの
/// 最大の強さ（sigma、2026-11-04）。
const slideBlurMaxSigma = 10.0;

/// 遷移中の滲むエフェクト。[amount]は0（くっきり）〜1（最大のぼかし）。
/// 0の間は`enabled: false`にするだけで、木の形（ウィジェットの種類）を変えない。
/// 有無で形が変わると子の画面が再マウントされるため、常にこのウィジェットを挟む。
Widget buildTransitionBlur(double amount, Widget child) {
  final sigma = (amount.clamp(0.0, 1.0)) * slideBlurMaxSigma;
  return ImageFiltered(
    enabled: sigma > 0.05,
    imageFilter: ImageFilter.blur(
      sigmaX: sigma,
      sigmaY: sigma,
      tileMode: TileMode.decal,
    ),
    child: child,
  );
}
