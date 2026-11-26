import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/app_ui_style.dart';
import '../../models/sticker.dart';
import '../../providers/app_ui_style_provider.dart';
import '../../theme/chalk/chalk_paint.dart';
import '../../theme/gekiga/gekiga_colors.dart';
import '../../utils/platform_info.dart';
import '../../widgets/glass/glass_surface.dart';
import '../../widgets/sticker_image.dart';
import 'sticker_carousel.dart';

/// メッセージ内容に応じたぺったん提案のパネル（2026-09-05追加、
/// `lib/utils/sticker_suggestion.dart`の`suggestStickers`が返す候補を
/// 入力欄の真上に表示する）。LINEの「おすすめスタンプ」がタップした
/// 時点でそのまま確定・送信される挙動（競合調査.md 2026-09-05付エントリ
/// 参照）に合わせ、通常のぺったんピッカー（`StickerPickerContent`）が持つ
/// LINE型2タップ・プレビュー挙動（`stickerSendMode`設定）とは独立に、
/// ここではタップ即送信にしている。
///
/// 2026-10-29: 背景の無い横並びで、メッセージ・背景に溶け込んで見づらかったため、
/// 枠付きのパネルにし、ぺったんを大きくした。入力欄エリアの**外**（入力欄の
/// 真上の別の層）に置く（入力欄の高さに含めると、「最新へジャンプ」ボタンが
/// 候補の出ている間だけ上にずれていた）。枠は3つのUIスタイルで分ける（劇画は
/// 黒地に白い太い縁、ガラスは浮遊カード、フラットは塗りと縁）。影は使わない。
class StickerSuggestionStrip extends ConsumerWidget {
  const StickerSuggestionStrip({
    required this.stickers,
    required this.onStickerTap,
    this.previewIndex,
    this.onPreviewIndexChanged,
    this.onPreviewSend,
    this.panelKey,
    super.key,
  });

  /// パネル本体（実際に見えている枠）に付けるキー。外側のクリックの判定と、パネルの
  /// 高さの計測に使う。
  final Key? panelKey;

  final List<Sticker> stickers;
  final void Function(Sticker sticker) onStickerTap;

  /// 拡大表示中の候補の添字（[stickers]の中）。nullなら一覧を見せる（2026-11-21）。
  /// LINEの「おすすめスタンプ」と同じく、パネルはその場で拡大表示に切り替わる。
  final int? previewIndex;
  final void Function(int index)? onPreviewIndexChanged;
  final void Function(Sticker sticker)? onPreviewSend;

  /// 一覧のぺったんの大きさ。スマホは画面を占めすぎないよう小さく、PC・タブレットは
  /// 大きく出す（2026-11-21、スマホを160→112に縮小）。
  static const _phoneStickerSize = 112.0;
  static const _wideStickerSize = 160.0;

  /// 拡大表示の時の、パネルの最低の高さ。スマホは一覧が小さいので、拡大ではパネルを
  /// 上へ広げる。PC・タブレットは一覧（2行）と同じ高さで、ぺったんのボタンから出す
  /// 拡大プレビュー（最大320）と同じ大きさになる。
  static const _phonePreviewMinHeight = 232.0;
  static const _widePreviewMinHeight = 344.0;
  static const _gap = 8.0;
  static const _padding = 8.0;
  static const _maxRows = 2;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uiStyle = ref.watch(appUiStyleProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final isGekiga = uiStyle == AppUiStyle.gekiga;
    final isGlass = uiStyle == AppUiStyle.glass;
    final radius = isGekiga ? BorderRadius.zero : BorderRadius.circular(12);

    // スマホは横1行（最大10件）で横スクロール、PC・タブレットは左に固めて
    // 最大2行に折り返し（ぺったんを68→160に拡大、2026-11-19）、入り切らない分は縦スクロール（2026-10-29）。
    final isPhone = classifyDevice(context) == DeviceClass.phone;
    final stickerSize = isPhone ? _phoneStickerSize : _wideStickerSize;
    final shown = isPhone ? stickers.take(10).toList() : stickers;
    Widget tile(Sticker sticker) => InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => onStickerTap(sticker),
      child: SizedBox(
        width: stickerSize,
        height: stickerSize,
        child: StickerImage(
          sticker.imageUrl,
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined),
        ),
      ),
    );
    final Widget list = isPhone
        ? SizedBox(
            height: stickerSize + _padding * 2,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.all(_padding),
              itemCount: shown.length,
              separatorBuilder: (_, _) => const SizedBox(width: _gap),
              itemBuilder: (context, index) => tile(shown[index]),
            ),
          )
        : ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight:
                  _maxRows * stickerSize + (_maxRows - 1) * _gap + _padding * 2,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(_padding),
              child: Wrap(
                spacing: _gap,
                runSpacing: _gap,
                children: [for (final s in shown) tile(s)],
              ),
            ),
          );

    final previewing = previewIndex != null && previewIndex! < stickers.length;
    // 一覧は拡大中も透明で残す。パネルの大きさが一覧で決まるので、拡大表示に
    // 切り替わっても位置・幅・高さが変わらない（LINEと同じクロスフェード）。
    final Widget stack = Stack(
      children: [
        IgnorePointer(
          ignoring: previewing,
          child: AnimatedOpacity(
            opacity: previewing ? 0 : 1,
            duration: const Duration(milliseconds: 150),
            child: list,
          ),
        ),
        if (previewing)
          Positioned.fill(
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: 1),
              duration: const Duration(milliseconds: 150),
              builder: (context, opacity, child) =>
                  Opacity(opacity: opacity, child: child),
              child: StickerCarousel(
                stickers: stickers,
                index: previewIndex!,
                onIndexChanged: onPreviewIndexChanged ?? (_) {},
                onSend: onPreviewSend ?? (_) {},
              ),
            ),
          ),
      ],
    );

    // 拡大表示の間は、パネルを最低の高さまで広げる（スマホは上へ伸びる）。
    final Widget content = AnimatedSize(
      duration: const Duration(milliseconds: 150),
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: previewing
              ? (isPhone ? _phonePreviewMinHeight : _widePreviewMinHeight)
              : 0,
        ),
        child: stack,
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        // 候補の数に合わせた内容幅（左寄せ）。入り切らない分は横スクロール。
        final contentWidth =
            shown.length * (stickerSize + _gap) - _gap + _padding * 2;
        // 拡大表示の間は、隣のぺったんが左右に見えるよう、パネルを広げる（隣の中心が0.85倍、隣の半幅が約0.275倍で、片側に約1.13倍要る）。
        final previewHeight = isPhone
            ? _phonePreviewMinHeight
            : _widePreviewMinHeight;
        final previewMinWidth = (previewHeight - 24).clamp(0.0, 320.0) * 2.4;
        final width = math.min(
          previewing ? math.max(contentWidth, previewMinWidth) : contentWidth,
          constraints.maxWidth,
        );
        final Widget panel;
        if (isGlass) {
          panel = GlassSurface(
            variant: GlassVariant.floating,
            borderRadius: radius,
            child: Material(type: MaterialType.transparency, child: content),
          );
        } else if (isGekiga) {
          panel = Material(
            color: GekigaColors.panel,
            shape: Border.all(color: GekigaColors.onPanel, width: 3),
            child: content,
          );
        } else if (uiStyle == AppUiStyle.chalk) {
          // チョーク: 黒板に、チョークで囲んだ枠。
          panel = Material(
            color: colorScheme.surfaceContainerHigh,
            shape: ChalkShapeBorder(
              borderRadius: radius,
              color: colorScheme.onSurface,
            ),
            child: content,
          );
        } else {
          panel = Material(
            color: colorScheme.surfaceContainerHigh,
            shape: RoundedRectangleBorder(
              borderRadius: radius,
              side: BorderSide(color: colorScheme.outlineVariant),
            ),
            child: content,
          );
        }
        return Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(key: panelKey, width: width, child: panel),
        );
      },
    );
  }
}
