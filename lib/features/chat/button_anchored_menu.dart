import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'talks_tab.dart' show kTalksSplitBreakpoint;

/// ボタン直下にポップアップを開くための位置を計算する（AppBarの
/// ピン留め・アルバム・ノート・投票・ハンバーガーメニュー各ボタンで
/// 重複していたロジックを共通化、2026-09-12追加）。
///
/// 横幅が狭い、または縦長の画面（`kTalksSplitBreakpoint`未満、または
/// width <= height）では、各ボタンごとに位置がばらつき窮屈な座標に
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
/// を子孫に公開するためのスコープ（2026-09-15追加）。`showMenu`でポップアップ
/// を開くと、Navigatorへのルートpushに伴うフォーカス変化等が原因と見られる
/// 形で背後のメッセージ一覧（`ScrollablePositionedList`）の表示位置が勝手に
/// ずれる不具合があったため、ポップアップの開閉とメッセージ一覧の表示状態を
/// 切り離す目的で導入した。`lib/widgets/interactive_swipe_back.dart`の
/// `InteractiveSwipeBackScope`と同じ形のスコープ。
class ChatScrollGuardScope extends InheritedWidget {
  const ChatScrollGuardScope({
    required this.beginPopup,
    required this.endPopup,
    required this.menuSwitcher,
    required super.child,
    super.key,
  });

  final VoidCallback beginPopup;
  final VoidCallback endPopup;

  /// ヘッダーのボタン同士で、ドロップダウンを開いたまま別のボタンへ直接切り
  /// 替えるための登録先（2026-10-10追加、[HeaderMenuSwitcher]参照）。
  final HeaderMenuSwitcher menuSwitcher;

  static ChatScrollGuardScope? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ChatScrollGuardScope>();

  @override
  bool updateShouldNotify(ChatScrollGuardScope oldWidget) => false;
}

/// ヘッダーのボタン（通話・ピン留め・アルバム・ノート・投票・カレンダー・
/// ハンバーガーメニュー等）を登録しておき、ドロップダウン表示中にその
/// ボタンが押されたとき、メニューを閉じてそのボタンの操作を実行できるように
/// する（2026-10-10追加）。`showMenu`のモーダルバリアは背後のボタンへの
/// タップを吸収してしまうため、バリアを押した位置をここで照合して代わりに
/// 実行する（[showAnchoredMenu]の`anchorKey`参照）。
class HeaderMenuSwitcher {
  final Map<GlobalKey, VoidCallback> _triggers = {};

  void register(GlobalKey key, VoidCallback onTap) => _triggers[key] = onTap;

  void unregister(GlobalKey key) => _triggers.remove(key);

  /// グローバル座標[position]にあるボタンの操作を返す（[except]は除く）。
  /// 矩形は左上・右下の2点を変換して作る（ヘッダー列が`FittedBox`で縮小
  /// されていても実際の見た目の領域で判定するため）。
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
  }

  guard?.beginPopup();
  if (switcher != null) {
    GestureBinding.instance.pointerRouter.addGlobalRoute(trackPointer);
  }
  T? result;
  try {
    result = await showMenu<T>(
      context: context,
      position: position,
      items: items,
      color: color,
      shadowColor: shadowColor,
      elevation: elevation,
    );
  } finally {
    if (switcher != null) {
      GestureBinding.instance.pointerRouter.removeGlobalRoute(trackPointer);
    }
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
