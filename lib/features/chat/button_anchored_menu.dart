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
