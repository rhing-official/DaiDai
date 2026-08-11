import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/sticker.dart';
import 'sticker_picker_content.dart';

/// デスクトップ幅（`kTalksSplitBreakpoint`以上）でのペタピタ送信アイコン
/// タップ時に、アイコンの近くにアンカー表示するポップアップ（2026-08-11
/// 追加）。メッセージ長押しメニュー（`chat_screen.dart`の
/// `_MessageBubbleTapAreaState._onLongPressStart`）と同じ
/// 「`Overlay`に直接`OverlayEntry`を差し込み、画面端でclampする」パターンで
/// 実装する（狭い幅の`showDialog`中央配置ではなく、Discordのペタピタ
/// ピッカーと同じくボタン付近に浮かせたいという要望のため）。
Future<Sticker?> showStickerPickerPopup(
  BuildContext context, {
  required GlobalKey anchorKey,
}) {
  final anchorBox = anchorKey.currentContext!.findRenderObject()! as RenderBox;
  final anchorTopLeft = anchorBox.localToGlobal(Offset.zero);
  final anchorRect = anchorTopLeft & anchorBox.size;

  final overlayBox =
      Overlay.of(context).context.findRenderObject()! as RenderBox;
  final screenSize = overlayBox.size;
  final colorScheme = Theme.of(context).colorScheme;

  const panelWidth = 360.0;
  const panelHeight = 420.0;
  const screenPad = 8.0;
  final left = (anchorRect.right - panelWidth).clamp(
    screenPad,
    screenSize.width - panelWidth - screenPad,
  );
  final top = (anchorRect.top - panelHeight - 8).clamp(
    screenPad,
    screenSize.height - panelHeight - screenPad,
  );

  final completer = Completer<Sticker?>();
  late final OverlayEntry entry;

  void close(Sticker? sticker) {
    if (completer.isCompleted) return;
    entry.remove();
    completer.complete(sticker);
  }

  entry = OverlayEntry(
    builder: (_) => Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => close(null),
            child: const ColoredBox(color: Colors.transparent),
          ),
        ),
        Positioned(
          left: left,
          top: top,
          width: panelWidth,
          height: panelHeight,
          child: Material(
            color: colorScheme.surfaceContainer,
            elevation: 8,
            shadowColor: colorScheme.shadow,
            borderRadius: const BorderRadius.all(Radius.circular(12)),
            clipBehavior: Clip.antiAlias,
            child: StickerPickerContent(
              railAxis: Axis.vertical,
              onStickerSelected: close,
            ),
          ),
        ),
      ],
    ),
  );
  Overlay.of(context).insert(entry);
  return completer.future;
}
