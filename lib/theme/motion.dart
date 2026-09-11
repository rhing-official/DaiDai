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

/// 画面右外から`Offset.zero`へ平行移動するだけの入場演出（フェード・拡大は
/// 付けない、2026-09-11追加）。`InteractiveSwipeBackTransition`が右スワイプで
/// 戻る時に行う`Transform.translate`（画面を右へ動かして背後を見せる）の
/// 逆再生に相当する見え方にすることで、寄合一覧を左スワイプ/タップで開いた
/// 時の入場アニメーションと、右スワイプで戻る動きを対称にする（`talks_tab.dart`
/// の`openRoomFullscreen`参照）。
Widget buildSlideInFromRightTransition(
  Animation<double> animation,
  Widget child,
) {
  final curved = CurvedAnimation(parent: animation, curve: popSlideCurve);
  return SlideTransition(
    position: Tween<Offset>(
      begin: const Offset(1, 0),
      end: Offset.zero,
    ).animate(curved),
    child: child,
  );
}
