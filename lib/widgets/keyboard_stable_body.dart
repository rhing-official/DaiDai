import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

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
/// Android・iOSだけで効く。Web・デスクトップは何もしない（物理キーボードで、
/// 画面が動く必要が無い）。
class KeyboardStableBody extends StatelessWidget {
  const KeyboardStableBody({required this.child, this.topClip = 0, super.key});

  final Widget child;

  /// キーボードが出ている間、上端からこの高さ（上部バーの下まで）の範囲は、ずらした中身を
  /// 描かない（上部バーの裏にメッセージが透けて通らないように）。キーボードが閉じて
  /// いる時は切らない（上部バーの裏までメッセージを伸ばす従来の見た目のまま）。
  /// 切る量は、ずらす量に応じて滑らかに0から[topClip]へ変わる。
  final double topClip;

  /// このプラットフォームで平行移動の方式を使うか。`Scaffold`の
  /// `resizeToAvoidBottomInset`は、この値の逆にする。
  static bool get enabledOnPlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  Widget build(BuildContext context) {
    if (!enabledOnPlatform) return child;
    final media = MediaQuery.of(context);
    final keyboard = media.viewInsets.bottom;
    final safeBottom = media.viewPadding.bottom;
    final shift = keyboard > safeBottom ? keyboard - safeBottom : 0.0;
    // Flutterは、キーボードが出ると`MediaQuery.padding.bottom`（入力欄の`SafeArea`が
    // 使う下の安全領域の余白）を自動で0にする。そのままだと入力欄の高さがキーボードの
    // 開閉中に変わり、ずらす量とも食い違う（キーボードが入力欄に重なる）。子には、
    // 余白を常に安全領域の高さのまま見せ、`shift`（キーボード − 安全領域）と合わせて
    // 入力欄の下端がキーボードの上端に付くようにする。
    final stable = MediaQuery(
      data: media.copyWith(padding: media.padding.copyWith(bottom: safeBottom)),
      child: child,
    );
    // 木の形は、キーボードの有無によらず常に同じにする（形が変わると子が作り直され、
    // メッセージ一覧の位置が失われる）。
    final ramp = (shift / 80).clamp(0.0, 1.0);
    return ClipRect(
      clipper: _TopInsetClipper(topClip * ramp),
      clipBehavior: shift > 0 ? Clip.hardEdge : Clip.none,
      child: Transform.translate(offset: Offset(0, -shift), child: stable),
    );
  }
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
