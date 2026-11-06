import 'dart:ui' show ImageFilter;

import 'package:flutter/widgets.dart';

import '../models/slide_transition_style.dart';
import '../widgets/liquify_effect.dart';

/// アプリ全体で使う「ポップ」演出（フェード＋下からのわずかなスライド＋
/// わずかな拡大）の共通パラメータ。元々`PopSlidePageTransitionsBuilder`
/// （`app_theme.dart`）のフルスクリーン画面遷移専用だったものを、設定/
/// 身だしなみのドリルダウン（`settings_tab.dart`/`profile_tab.dart`の
/// `AnimatedSwitcher`）でも同じモーション言語になるよう共通化した
/// （2026-08-10追加）。
/// 今の画面遷移の種類（2026-11-04）。遷移の組み立て関数は`ref`/`context`を持たない為、
/// `slideTransitionStyleProvider`が設定の変更・同期・起動時の読み込みのたびに更新する。
/// 遷移の組み立ては毎フレーム呼ばれるので、その時点の値が使われる。
SlideTransitionStyle activeSlideTransitionStyle =
    SlideTransitionStyle.slideBlur;

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
  final style = activeSlideTransitionStyle;
  final curved = CurvedAnimation(parent: animation, curve: popSlideCurve);
  // 離れているほど滲ませる（2026-11-04）。
  // ポップ: 中央から弾むように拡大して現れる（2026-11-06）。
  if (style == SlideTransitionStyle.pop) {
    return FadeTransition(
      opacity: curved,
      child: ScaleTransition(
        scale: Tween<double>(
          begin: popMinScale,
          end: 1,
        ).animate(CurvedAnimation(parent: animation, curve: popScaleCurve)),
        child: child,
      ),
    );
  }
  final blurred = AnimatedBuilder(
    animation: curved,
    child: child,
    builder: (context, child) => buildTransitionBlur(
      1 - curved.value,
      // 吸い込みの液状化（種類に関わらず常に挟み、`enabled`だけで切り替える）。
      LiquifyEffect(
        progress: 1 - curved.value,
        enabled: style == SlideTransitionStyle.suck,
        child: child!,
      ),
    ),
  );
  // 吸い込み: 右下の角から広がる／右下の角へ縮む（2026-11-04、初版）。
  if (style == SlideTransitionStyle.suck) {
    return FadeTransition(
      opacity: curved,
      child: ScaleTransition(
        alignment: Alignment.bottomRight,
        scale: Tween<double>(begin: suckMinScale, end: 1).animate(curved),
        child: blurred,
      ),
    );
  }
  final slid = SlideTransition(
    position: Tween<Offset>(
      begin: const Offset(1, 0),
      end: Offset.zero,
    ).animate(curved),
    child: blurred,
  );
  if (style == SlideTransitionStyle.slide) return slid;
  // スライドに合わせて薄い状態から濃くなる（戻る時は逆再生で薄くなる）、2026-11-02。
  return FadeTransition(opacity: curved, child: slid);
}

/// 「ポップ」で、現れ始めの画面の拡大率（中央から広がる）と、その動きの曲線
/// （少し行き過ぎて弾む）。語らい一覧の「＋」で開くポップアップの動きと同じ。
const popMinScale = 0.6;
const popScaleCurve = Curves.easeOutBack;

/// 「吸い込み」のダイアログで、不透明度が1になる進行度（0〜1）。閉じる時は、進行度が
/// これを下回ってから薄くなり始める（それまでは縮みながらはっきり見える）。
const suckFadeEnd = 0.08;

/// 「吸い込み」で、消え切った時の画面の拡大率（右下の角へ縮む先）。
const suckMinScale = 0.1;

/// 画面遷移で、重なるページが離れるほど（[amount]が1に近いほど）滲むぼかしの
/// 最大の強さ（sigma、2026-11-04）。
const slideBlurMaxSigma = 10.0;

/// 遷移中の滲むエフェクト。[amount]は0（くっきり）〜1（最大のぼかし）。
/// 0の間は`enabled: false`にするだけで、木の形（ウィジェットの種類）を変えない。
/// 有無で形が変わると子の画面が再マウントされる為、常にこのウィジェットを挟む。
Widget buildTransitionBlur(double amount, Widget child) {
  // ぼかしを使わない種類では常に無効（ウィジェット自体は挟み続ける）。
  final sigma = activeSlideTransitionStyle.usesBlur
      ? (amount.clamp(0.0, 1.0)) * slideBlurMaxSigma
      : 0.0;
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

/// 指のドラッグに追従して画面が現れる／消える動きを、今の画面遷移の種類で描く
/// （2026-11-04）。[away]は0（全表示）〜1（消え切る）、[maxDrag]は画面幅（px）。
/// 寄合一覧を左スワイプしてメッセージ画面を開く時のプレビューなど、`Route`を
/// 使わない場所で、スライド＋滲み・スライド・吸い込みを揃える為に使う。
/// 木の形は種類によらず固定（`Transform`・`Opacity`・`ImageFiltered`・
/// `LiquifyEffect`を常に挟む）。
Widget buildAwayTransition({
  required double away,
  required double maxDrag,
  required Widget child,
}) {
  final style = activeSlideTransitionStyle;
  final isSuck = style == SlideTransitionStyle.suck;
  final progress = away.clamp(0.0, 1.0);
  final isPop = style == SlideTransitionStyle.pop;
  final scale = isSuck
      ? 1 - (1 - suckMinScale) * progress
      : (isPop ? 1 - (1 - popMinScale) * progress : 1.0);
  final moved = Transform(
    alignment: isPop ? Alignment.center : Alignment.bottomRight,
    transform: Matrix4.identity()
      ..translateByDouble(isSuck ? 0.0 : progress * maxDrag, 0.0, 0.0, 1.0)
      ..scaleByDouble(scale, scale, 1.0, 1.0),
    child: LiquifyEffect(progress: progress, enabled: isSuck, child: child),
  );
  return Opacity(
    opacity: style.usesFade ? 1 - progress : 1.0,
    child: buildTransitionBlur(progress, moved),
  );
}

/// ダイアログ・ポップアップ・拡大表示の開閉の動き（2026-11-05）。今の画面遷移の種類に従う。
/// [animation]は0（無い）→1（全表示）。背景の暗幕は呼び出し側のルートが別にフェードさせる。
/// - スライド＋滲み: 薄い・ぼやけた状態から現れる（スライドなし）。
/// - スライド: 下からスライドして現れる。
/// - 吸い込み: 右下の角から広がり、液状化しながら現れる（閉じる時は逆）。
/// 木の形は種類によらず固定する（再マウント防止）。
Widget buildDialogTransition(Animation<double> animation, Widget child) {
  final style = activeSlideTransitionStyle;
  final isSuck = style == SlideTransitionStyle.suck;
  // 吸い込みで開く時は、先に急に大きくならず右下の角から広がる様子が見えるよう、
  // 立ち上がりのゆるい曲線にする（閉じる時は従来の曲線のまま、2026-11-05）。
  final curved = CurvedAnimation(
    parent: animation,
    curve: isSuck ? Curves.easeInOutCubic : popSlideCurve,
    reverseCurve: popSlideCurve,
  );
  final isSlide = style == SlideTransitionStyle.slide;
  final isPop = style == SlideTransitionStyle.pop;
  // ポップは、開く時に少し行き過ぎて弾む曲線（閉じる時は通常の曲線）。
  final popCurved = CurvedAnimation(
    parent: animation,
    curve: popScaleCurve,
    reverseCurve: popSlideCurve,
  );
  return AnimatedBuilder(
    animation: Listenable.merge([curved, popCurved]),
    child: child,
    builder: (context, child) {
      final away = 1 - curved.value;
      final scale = isSuck
          ? suckMinScale + (1 - suckMinScale) * curved.value
          : (isPop ? popMinScale + (1 - popMinScale) * popCurved.value : 1.0);
      // 基点は子の枠ではなく画面の右下（アルバムなど小さなポップアップでも、画面の隅から
      // 現れ／へ吸い込まれる）。
      final inner = ScreenCornerScale(
        scale: scale,
        corner: isPop ? Alignment.center : Alignment.bottomRight,
        child: LiquifyEffect(progress: away, enabled: isSuck, child: child!),
      );
      return FractionalTranslation(
        translation: Offset(0, isSlide ? away * 0.4 : 0),
        child: Opacity(
          // 現れ始めは薄くする（どの種類でも、唐突に出ないように）。吸い込みは、縮みながら
          // 右下へ消えていく様子が見えるよう、最後の少しだけ薄くする（以前は線形に
          // 薄くした為、縮み切る前に見えなくなっていた、2026-11-05）。
          opacity: isSuck
              ? (curved.value / suckFadeEnd).clamp(0.0, 1.0)
              : curved.value.clamp(0.0, 1.0),
          child: buildTransitionBlur(away, inner),
        ),
      );
    },
  );
}

/// トグル（スイッチ・チェックボックス・ラジオ）と押した時の手応えの共通パラメータ
/// （2026-11-05）。弾むバネ＝`easeOutBack`で少し行き過ぎてから戻る。
const springDuration = Duration(milliseconds: 280);
const springCurve = Curves.easeOutBack;
const pressDuration = Duration(milliseconds: 110);
const pressScale = 0.96;

/// 端末の「動きを減らす」設定が有効か。有効ならトグルは動かさずに即切り替える。
bool reduceMotion(BuildContext context) =>
    MediaQuery.maybeDisableAnimationsOf(context) ?? false;
