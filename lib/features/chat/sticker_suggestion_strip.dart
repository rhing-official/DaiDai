import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/app_ui_style.dart';
import '../../models/sticker.dart';
import '../../providers/app_ui_style_provider.dart';
import '../../theme/gekiga/gekiga_colors.dart';
import '../../utils/platform_info.dart';
import '../../widgets/glass/glass_surface.dart';

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
    super.key,
  });

  final List<Sticker> stickers;
  final void Function(Sticker sticker) onStickerTap;

  static const _stickerSize = 68.0;
  static const _gap = 8.0;
  static const _padding = 8.0;
  static const _maxRows = 3;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uiStyle = ref.watch(appUiStyleProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final isGekiga = uiStyle == AppUiStyle.gekiga;
    final isGlass = uiStyle == AppUiStyle.glass;
    final radius = isGekiga ? BorderRadius.zero : BorderRadius.circular(12);

    // スマホは横1行（最大10件）で横スクロール、PC・タブレットは左に固めて
    // 最大3行に折り返し、入り切らない分は縦スクロール（2026-10-29）。
    final isPhone = classifyDevice(context) == DeviceClass.phone;
    final shown = isPhone ? stickers.take(10).toList() : stickers;
    Widget tile(Sticker sticker) => InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => onStickerTap(sticker),
      child: SizedBox(
        width: _stickerSize,
        height: _stickerSize,
        child: Image.network(
          sticker.imageUrl,
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined),
        ),
      ),
    );
    final Widget list = isPhone
        ? SizedBox(
            height: _stickerSize + _padding * 2,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.all(_padding),
              itemCount: shown.length,
              separatorBuilder: (_, _) => const SizedBox(width: _gap),
              itemBuilder: (context, index) => tile(shown[index]),
            ),
          )
        : ConstrainedBox(
            constraints: const BoxConstraints(
              maxHeight:
                  _maxRows * _stickerSize +
                  (_maxRows - 1) * _gap +
                  _padding * 2,
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

    return LayoutBuilder(
      builder: (context, constraints) {
        // 候補の数に合わせた内容幅（左寄せ）。入り切らない分は横スクロール。
        final contentWidth =
            shown.length * (_stickerSize + _gap) - _gap + _padding * 2;
        final width = math.min(contentWidth, constraints.maxWidth);
        final Widget panel;
        if (isGlass) {
          panel = GlassSurface(
            variant: GlassVariant.floating,
            borderRadius: radius,
            child: Material(type: MaterialType.transparency, child: list),
          );
        } else if (isGekiga) {
          panel = Material(
            color: GekigaColors.panel,
            shape: Border.all(color: GekigaColors.onPanel, width: 3),
            child: list,
          );
        } else {
          panel = Material(
            color: colorScheme.surfaceContainerHigh,
            shape: RoundedRectangleBorder(
              borderRadius: radius,
              side: BorderSide(color: colorScheme.outlineVariant),
            ),
            child: list,
          );
        }
        return Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(width: width, child: panel),
        );
      },
    );
  }
}
