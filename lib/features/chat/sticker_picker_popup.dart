import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/app_ui_style.dart';
import '../../models/sticker.dart';
import '../../providers/app_ui_style_provider.dart';
import 'sticker_picker_content.dart';

/// デスクトップ幅（`kTalksSplitBreakpoint`以上）でのぺったん送信アイコン
/// タップ時、および所持済みパックのぺったんをメッセージ上でタップした際
/// （2026-08-14〜、`chat_screen.dart`の`_handleStickerTap`）に、アンカー
/// 近くに表示するポップアップ（2026-08-11追加）。メッセージ長押しメニュー
/// （`chat_screen.dart`の`_MessageBubbleTapAreaState._onLongPressStart`）と
/// 同じ「`Overlay`に直接`OverlayEntry`を差し込み、画面端でclampする」
/// パターンで実装する（狭い幅の`showDialog`中央配置ではなく、Discordの
/// ぺったんピッカーと同じくアンカー付近に浮かせたいという要望のため）。
/// アンカー矩形は呼び出し側で計算して渡す（送信アイコンは永続的な
/// `GlobalKey`から、メッセージタップは呼び出し時の`BuildContext`から、と
/// 起点が異なるため）。
Future<Sticker?> showStickerPickerPopup(
  BuildContext context, {
  required Rect anchorRect,
  String? initialPackId,
}) {
  final overlayBox =
      Overlay.of(context).context.findRenderObject()! as RenderBox;
  final screenSize = overlayBox.size;
  final colorScheme = Theme.of(context).colorScheme;
  // 劇画UIでは、黒いパネルではなく劇画の背景色（アクセント）で表示する（2026-10-29）。
  final isGekiga =
      ProviderScope.containerOf(
        context,
        listen: false,
      ).read(appUiStyleProvider) ==
      AppUiStyle.gekiga;

  const panelWidth = 360.0;
  const panelHeight = 420.0;
  const screenPad = 8.0;
  // 右下の「最新へジャンプ」ボタンに重ならないよう、右端をその分だけ左へずらす。
  const jumpButtonClearance = 64.0;
  final left = (anchorRect.right - panelWidth - jumpButtonClearance).clamp(
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
            // translucent: 背面のメッセージ一覧のスクロール（ホイール・ドラッグ）を
            // ポップアップ表示中も通す。外側のタップは従来どおりこちらが受けて
            // 閉じる（背面のタップにはならない、2026-10-29）。
            behavior: HitTestBehavior.translucent,
            onTap: () => close(null),
            // ColoredBoxは常に当たり判定を持ち背面を塞ぐため使わない。
            child: const SizedBox.expand(),
          ),
        ),
        Positioned(
          left: left,
          top: top,
          width: panelWidth,
          height: panelHeight,
          child: Material(
            color: isGekiga
                ? colorScheme.surface
                : colorScheme.surfaceContainer,
            elevation: 8,
            shadowColor: colorScheme.shadow,
            borderRadius: const BorderRadius.all(Radius.circular(12)),
            clipBehavior: Clip.antiAlias,
            child: StickerPickerContent(
              railAxis: Axis.vertical,
              initialPackId: initialPackId,
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
