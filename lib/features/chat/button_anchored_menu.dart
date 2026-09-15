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
    required super.child,
    super.key,
  });

  final VoidCallback beginPopup;
  final VoidCallback endPopup;

  static ChatScrollGuardScope? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ChatScrollGuardScope>();

  @override
  bool updateShouldNotify(ChatScrollGuardScope oldWidget) => false;
}

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
}) async {
  final guard = ChatScrollGuardScope.maybeOf(context);
  guard?.beginPopup();
  try {
    return await showMenu<T>(
      context: context,
      position: position,
      items: items,
      color: color,
      shadowColor: shadowColor,
      elevation: elevation,
    );
  } finally {
    guard?.endPopup();
  }
}
