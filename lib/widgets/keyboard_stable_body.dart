import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../utils/ime_progress.dart';

/// ソフトキーボードの開閉に合わせて、`Scaffold`のbody全体を上下に平行移動して見せる
/// （2026-11-12）。
///
/// 使う側の`Scaffold`は`resizeToAvoidBottomInset: false`にして、bodyを縮めさせない
/// （[enabledOnPlatform]がtrueの時だけ）。bodyは常に画面いっぱいの高さのまま
/// レイアウトされ、一覧のビューポートも入力欄の高さも変わらない。キーボードの高さ
/// 1つだけを基準に、描画を上へずらす。縮める量と戻す量を別々のタイミングで合わせる
/// 方式では、わずかなずれが「通り過ぎて戻る」動きに見えていた。
///
/// ずらす量は`max(キーボードの高さ − 下の安全領域, 0)`。入力欄は下の安全領域
/// （ナビゲーションバー分）の余白を常に持ったままで高さが変わらず（子に見せる
/// `MediaQuery.padding.bottom`を一定にする）、ずらした結果、入力欄の下端がキーボードの
/// 上端にぴったり付く。外側の`Scaffold`が
/// すでに縮めている（`MediaQuery`のキーボードの高さが0）場合は、ずらさない。
/// `AppBar`は`Scaffold`側に残り、固定のまま。
///
/// キーボードによる移動はAndroid・iOSだけで効く。Web・デスクトップは何もしない
/// （物理キーボードで、画面が動く必要が無い）。[extraShift]は全プラットフォームで効く。
class KeyboardStableBody extends StatelessWidget {
  const KeyboardStableBody({
    required this.child,
    this.topClip = 0,
    this.extraShift = 0,
    super.key,
  });

  final Widget child;

  /// キーボードが出ている間、上端からこの高さ（上部バーの下まで）の範囲は、ずらした中身を
  /// 描かない（上部バーの裏にメッセージが透けて通らないように）。キーボードが閉じて
  /// いる時は切らない（上部バーの裏までメッセージを伸ばす従来の見た目のまま）。
  /// 切る量は、ずらす量に応じて滑らかに0から[topClip]へ変わる。
  final double topClip;

  /// キーボードとは別に、本体を上へずらす量（ぺったんドックの高さ − 下の安全領域、
  /// 2026-11-21）。ドックは画面下端に重ねて置き、本体を縮めずにずらす（縮めると
  /// 一覧のビューポートと入力欄の高さが変わり、メッセージが跳ねる）。キーボードと
  /// 違い、Webを含む全プラットフォームで効く。ずらす量は、キーボード由来の量と
  /// この値の大きい方。
  final double extraShift;

  /// このプラットフォームで平行移動の方式を使うか。`Scaffold`の
  /// `resizeToAvoidBottomInset`は、この値の逆にする。
  static bool get enabledOnPlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  Widget build(BuildContext context) {
    final enabled = enabledOnPlatform;
    final media = MediaQuery.of(context);
    final safeBottom = media.viewPadding.bottom;
    if (enabled) ImeProgress.ensureInitialized();
    // Flutterは、キーボードが出ると`MediaQuery.padding.bottom`（入力欄の`SafeArea`が
    // 使う下の安全領域の余白）を自動で0にする。そのままだと入力欄の高さがキーボードの
    // 開閉中に変わり、ずらす量とも食い違う（キーボードが入力欄に重なる）。子には、
    // 余白を常に安全領域の高さのまま見せ、`shift`（キーボード − 安全領域）と合わせて
    // 入力欄の下端がキーボードの上端に付くようにする。
    final stable = enabled
        ? MediaQuery(
            data: media.copyWith(
              padding: media.padding.copyWith(bottom: safeBottom),
            ),
            child: child,
          )
        : child;
    // 木の形は、キーボードの有無によらず常に同じにする（形が変わると子が作り直され、
    // メッセージ一覧の位置が失われる）。
    //
    // キーボード由来のずらす量（2026-11-21）。Androidでは、OSのキーボードの動きの途中の
    // 高さ（[ImeProgress.live]）をそのまま使い、キーボードと一緒に動かす。FlutterのviewInsetsは
    // 実機（Android 16）で、動きが終わった後に1回だけ最終値で届く為、それを基準にすると
    // キーボードより遅れていた。途中の高さが届かない端末・OSでは、viewInsetsを250msで補間する。
    return ValueListenableBuilder<double?>(
      valueListenable: ImeProgress.live,
      child: stable,
      builder: (context, liveInset, child) {
        final keyboard = !enabled
            ? 0.0
            : (liveInset ?? media.viewInsets.bottom);
        final keyboardShift = keyboard > safeBottom
            ? keyboard - safeBottom
            : 0.0;
        return TweenAnimationBuilder<double>(
          tween: Tween<double>(end: keyboardShift),
          duration: (enabled && liveInset == null)
              ? _keyboardDuration
              : Duration.zero,
          curve: Curves.easeOutCubic,
          child: child,
          builder: (context, animatedKeyboardShift, child) {
            final shift = animatedKeyboardShift > extraShift
                ? animatedKeyboardShift
                : extraShift;
            final ramp = (shift / 80).clamp(0.0, 1.0);
            return ClipRect(
              clipper: _TopInsetClipper(topClip * ramp),
              clipBehavior: shift > 0 ? Clip.hardEdge : Clip.none,
              child: Transform.translate(
                offset: Offset(0, -shift),
                child: child,
              ),
            );
          },
        );
      },
    );
  }

  static const _keyboardDuration = Duration(milliseconds: 250);
}

/// 上端から[top]だけ内側を切り口にする（左右・下は元の大きさ）。
class _TopInsetClipper extends CustomClipper<Rect> {
  const _TopInsetClipper(this.top);

  final double top;

  @override
  Rect getClip(Size size) => Rect.fromLTRB(0, top, size.width, size.height);

  @override
  bool shouldReclip(_TopInsetClipper oldClipper) => oldClipper.top != top;
}
