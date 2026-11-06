import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../theme/motion.dart';
import 'talks_tab.dart' show kTalksSplitBreakpoint;

/// ボタン直下にポップアップを開くための位置を計算する（AppBarの
/// ピン留め・アルバム・ノート・投票・ハンバーガーメニュー各ボタンで
/// 重複していたロジックを共通化、2026-09-12追加）。
///
/// 横幅が狭い、又は縦長の画面（`kTalksSplitBreakpoint`未満、又は
/// width <= height）では、各ボタン毎に位置がばらつき窮屈な座標に
/// なりやすいため（実機確認で発覚）、[narrowAnchorKey]（通常はハンバーガー
/// メニューボタンのキー）が渡されていればそちらの矩形を基準に統一する。
/// PC・タブレットの横表示では従来通り[buttonKey]自身の直下に開く。
RelativeRect? computeButtonAnchoredMenuPosition(
  BuildContext context, {
  required GlobalKey buttonKey,
  GlobalKey? narrowAnchorKey,
}) {
  final size = MediaQuery.sizeOf(context);
  final isWideLandscape =
      size.width >= kTalksSplitBreakpoint && size.width > size.height;
  final effectiveKey =
      (!isWideLandscape && narrowAnchorKey?.currentContext != null)
      ? narrowAnchorKey!
      : buttonKey;
  final buttonContext = effectiveKey.currentContext;
  if (buttonContext == null) return null;
  final box = buttonContext.findRenderObject()! as RenderBox;
  final bottomLeft = box.localToGlobal(Offset(0, box.size.height));
  final bottomRight = box.localToGlobal(
    Offset(box.size.width, box.size.height),
  );
  final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
  return RelativeRect.fromRect(
    Rect.fromPoints(bottomLeft, bottomRight),
    Offset.zero & overlay.size,
  );
}

/// [ChatScreen]がメッセージ一覧のスクロール位置保護（[showAnchoredMenu]参照）
/// を子孫に公開する為のスコープ（2026-09-15追加）。`showMenu`でポップアップ
/// を開くと、Navigatorへのルートpushに伴うフォーカス変化等が原因と見られる
/// 形で背後のメッセージ一覧（`ScrollablePositionedList`）の表示位置が勝手に
/// ずれる不具合があった為、ポップアップの開閉とメッセージ一覧の表示状態を
/// 切り離す目的で導入した。`lib/widgets/interactive_swipe_back.dart`の
/// `InteractiveSwipeBackScope`と同じ形のスコープ。
class ChatScrollGuardScope extends InheritedWidget {
  const ChatScrollGuardScope({
    required this.beginPopup,
    required this.endPopup,
    required this.menuSwitcher,
    required this.scrollBy,
    required super.child,
    super.key,
  });

  final VoidCallback beginPopup;
  final VoidCallback endPopup;

  /// ポップアップを開いたままメッセージ一覧をスクロールする（2026-11-02）。引数は
  /// スクロール位置への加算量（px、正が古いメッセージ側＝画面の下へ内容が動く向き）。
  final void Function(double delta) scrollBy;

  /// ヘッダーのボタン同士で、ドロップダウンを開いたまま別のボタンへ直接切り
  /// 替える為の登録先（2026-10-10追加、[HeaderMenuSwitcher]参照）。
  final HeaderMenuSwitcher menuSwitcher;

  static ChatScrollGuardScope? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ChatScrollGuardScope>();

  @override
  bool updateShouldNotify(ChatScrollGuardScope oldWidget) => false;
}

/// ヘッダーのボタン（通話・ピン留め・アルバム・ノート・投票・カレンダー・
/// ハンバーガーメニュー等）を登録しておき、ドロップダウン表示中にその
/// ボタンが押された時、メニューを閉じてそのボタンの操作を実行出来るように
/// する（2026-10-10追加）。`showMenu`のモーダルバリアは背後のボタンへの
/// タップを吸収してしまうため、バリアを押した位置をここで照合して代わりに
/// 実行する（[showAnchoredMenu]の`anchorKey`参照）。
class HeaderMenuSwitcher {
  final Map<GlobalKey, VoidCallback> _triggers = {};

  void register(GlobalKey key, VoidCallback onTap) => _triggers[key] = onTap;

  void unregister(GlobalKey key) => _triggers.remove(key);

  /// グローバル座標[position]にあるボタンの操作を返す（[except]は除く）。
  /// 矩形は左上・右下の2点を変換して作る（ヘッダー列が`FittedBox`で縮小
  /// されていても実際の見た目の領域で判定する為）。
  VoidCallback? triggerAt(Offset position, {GlobalKey? except}) {
    for (final entry in _triggers.entries) {
      if (entry.key == except) continue;
      final renderObject = entry.key.currentContext?.findRenderObject();
      if (renderObject is! RenderBox ||
          !renderObject.attached ||
          !renderObject.hasSize) {
        continue;
      }
      final topLeft = renderObject.localToGlobal(Offset.zero);
      final bottomRight = renderObject.localToGlobal(
        renderObject.size.bottomRight(Offset.zero),
      );
      if (Rect.fromPoints(topLeft, bottomRight).contains(position)) {
        return entry.value;
      }
    }
    return null;
  }
}

/// [context]の祖先の[ChatScrollGuardScope]へヘッダーのボタン[key]を登録し、
/// 解除用の関数を返す（スコープが無ければnull）。ボタンの`initState`で呼び、
/// `dispose`で返り値を呼ぶ。
VoidCallback? registerHeaderMenuTrigger(
  BuildContext context,
  GlobalKey key,
  VoidCallback onTap,
) {
  final switcher = ChatScrollGuardScope.maybeOf(context)?.menuSwitcher;
  if (switcher == null) return null;
  switcher.register(key, onTap);
  return () => switcher.unregister(key);
}

/// 2つの表示位置が実質同じか（メニューを閉じた時の位置復元を省けるか、
/// 2026-10-10追加）。復元ジャンプ自体が最新メッセージ表示中に一覧を動かして
/// しまう不具合の対策で、位置が変わっていなければジャンプしない。
bool isSameItemPosition({
  required int indexA,
  required double leadingEdgeA,
  required int indexB,
  required double leadingEdgeB,
}) => indexA == indexB && (leadingEdgeA - leadingEdgeB).abs() < 0.002;

/// `showMenu`の薄いラッパー（2026-09-15追加）。祖先に[ChatScrollGuardScope]
/// があれば、ポップアップを開いている間メッセージ一覧のスクロール位置が
/// ずれないよう保護する。スコープが無い文脈（チャット画面以外）では通常の
/// `showMenu`と同じ挙動になる。
Future<T?> showAnchoredMenu<T>({
  required BuildContext context,
  required RelativeRect position,
  required List<PopupMenuEntry<T>> items,
  Color? color,
  Color? shadowColor,
  double? elevation,
  GlobalKey? anchorKey,
}) async {
  final guard = ChatScrollGuardScope.maybeOf(context);
  // [anchorKey]（このメニューを開いたヘッダーのボタン自身のキー）を渡すと、
  // メニューを開いたまま別のヘッダーのボタンを押した時に、メニューを閉じて
  // そのボタンの操作を続けて実行する（2026-10-10追加、[HeaderMenuSwitcher]
  // 参照）。省略時は従来どおり閉じるだけ。
  final switcher = anchorKey == null ? null : guard?.menuSwitcher;
  Offset? lastDown;
  void trackPointer(PointerEvent event) {
    if (event is PointerDownEvent) lastDown = event.position;
    // メニューを開いたまま、背後のメッセージ一覧をスクロール出来るようにする
    // （2026-11-02）。モーダルバリアは一覧へのスクロールを吸収する為、ポインタを
    // 直接拾って一覧へ流す。マウスはホイール、タッチ・ペンはドラッグ。タップはバリアが
    // 閉じる操作のまま（動かさなければ何も流れない）。
    if (event is PointerScrollEvent) {
      guard?.scrollBy(-event.scrollDelta.dy);
    } else if (event is PointerMoveEvent &&
        event.kind != PointerDeviceKind.mouse) {
      guard?.scrollBy(event.delta.dy);
    }
  }

  guard?.beginPopup();
  GestureBinding.instance.pointerRouter.addGlobalRoute(trackPointer);
  T? result;
  try {
    // 内容だけを透明な枠に載せるポップアップ（アルバム・ノート・カレンダー・投票）は、
    // 素の`showMenu`ではなく、画面遷移の種類に従う開閉の動きで画面の右下から現れる自前の
    // ルートで出す（2026-11-05。`showMenu`のルートは開閉の動きを差し替えられない）。
    final first = items.length == 1 ? items.first : null;
    final Widget? popupChild =
        first is PopupMenuItem<T> &&
            !first.enabled &&
            color == Colors.transparent
        ? first.child
        : null;
    if (popupChild != null) {
      final navigator = Navigator.of(context, rootNavigator: true);
      result = await navigator.push<T>(
        _AnchoredPopupRoute<T>(
          position: position,
          themes: InheritedTheme.capture(from: context, to: navigator.context),
          barrierLabel: MaterialLocalizations.of(
            context,
          ).modalBarrierDismissLabel,
          child: popupChild,
        ),
      );
    } else {
      result = await showMenu<T>(
        context: context,
        position: position,
        items: items,
        color: color,
        shadowColor: shadowColor,
        elevation: elevation,
      );
    }
  } finally {
    GestureBinding.instance.pointerRouter.removeGlobalRoute(trackPointer);
    guard?.endPopup();
  }
  final downAt = lastDown;
  if (result == null && switcher != null && downAt != null) {
    final trigger = switcher.triggerAt(downAt, except: anchorKey);
    if (trigger != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => trigger());
    }
  }
  return result;
}

/// 内容だけを載せるアンカー付きポップアップのルート（2026-11-05）。位置は`showMenu`と
/// 同じ規則（[position]の左上、はみ出す側は反対側へ寄せ、画面の端から8px空ける）。
/// 開閉は`buildDialogTransition`（画面遷移の種類に従う、吸い込みは画面の右下基点）。
class _AnchoredPopupRoute<T> extends PopupRoute<T> {
  _AnchoredPopupRoute({
    required this.position,
    required this.themes,
    required this.child,
    required this.barrierLabel,
  });

  final RelativeRect position;
  final CapturedThemes themes;
  final Widget child;

  @override
  final String barrierLabel;

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => true;

  @override
  Duration get transitionDuration => popSlideDuration;

  @override
  Duration get reverseTransitionDuration => popSlideDuration;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final padding = MediaQuery.paddingOf(context);
    return CustomSingleChildLayout(
      delegate: _AnchoredPopupLayout(
        position: position,
        padding: padding,
        textDirection: Directionality.of(context),
      ),
      child: themes.wrap(
        Material(
          type: MaterialType.transparency,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 112, maxWidth: 280),
            child: IntrinsicWidth(stepWidth: 56, child: child),
          ),
        ),
      ),
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => buildDialogTransition(animation, child);
}

class _AnchoredPopupLayout extends SingleChildLayoutDelegate {
  _AnchoredPopupLayout({
    required this.position,
    required this.padding,
    required this.textDirection,
  });

  final RelativeRect position;
  final EdgeInsets padding;
  final TextDirection textDirection;

  static const _screenPadding = 8.0;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    return BoxConstraints.loose(
      constraints.biggest,
    ).deflate(const EdgeInsets.all(_screenPadding) + padding);
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final y = position.top;
    final double x;
    if (position.left > position.right) {
      x = size.width - position.right - childSize.width;
    } else if (position.left < position.right) {
      x = position.left;
    } else {
      x = textDirection == TextDirection.rtl
          ? size.width - position.right - childSize.width
          : position.left;
    }
    return Offset(
      _clamp(
        x,
        _screenPadding + padding.left,
        size.width - childSize.width - _screenPadding - padding.right,
      ),
      _clamp(
        y,
        _screenPadding + padding.top,
        size.height - childSize.height - _screenPadding - padding.bottom,
      ),
    );
  }

  static double _clamp(double value, double min, double max) =>
      max < min ? min : value.clamp(min, max);

  @override
  bool shouldRelayout(_AnchoredPopupLayout oldDelegate) =>
      position != oldDelegate.position ||
      padding != oldDelegate.padding ||
      textDirection != oldDelegate.textDirection;
}
