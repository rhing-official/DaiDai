import 'dart:math' as math;
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/app_ui_style.dart';
import '../../models/sticker.dart';
import '../../providers/app_ui_style_provider.dart';
import '../../theme/gekiga/gekiga_colors.dart';
import '../../utils/platform_info.dart';
import '../../widgets/glass/glass_surface.dart';
import '../../widgets/sticker_image.dart';

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
    this.onPreviewClose,
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
  final VoidCallback? onPreviewClose;
  final void Function(Sticker sticker)? onPreviewSend;

  static const _stickerSize = 160.0;
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
    final shown = isPhone ? stickers.take(10).toList() : stickers;
    Widget tile(Sticker sticker) => InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => onStickerTap(sticker),
      child: SizedBox(
        width: _stickerSize,
        height: _stickerSize,
        child: StickerImage(
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

    final previewing = previewIndex != null && previewIndex! < stickers.length;
    // 一覧は拡大中も透明で残す。パネルの大きさが一覧で決まるので、拡大表示に
    // 切り替わっても位置・幅・高さが変わらない（LINEと同じクロスフェード）。
    final Widget content = Stack(
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
              child: StickerSuggestionPreview(
                stickers: stickers,
                index: previewIndex!,
                onIndexChanged: onPreviewIndexChanged ?? (_) {},
                onSend: onPreviewSend ?? (_) {},
                onClose: onPreviewClose ?? () {},
              ),
            ),
          ),
      ],
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
            child: Material(type: MaterialType.transparency, child: content),
          );
        } else if (isGekiga) {
          panel = Material(
            color: GekigaColors.panel,
            shape: Border.all(color: GekigaColors.onPanel, width: 3),
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

/// 提案ぺったんの拡大表示（2026-11-21、LINEの「おすすめスタンプ」と同じ見せ方）。
/// 選んだぺったんを中央に大きく出し、左右に隣の候補を小さく薄く覗かせる。横スワイプで
/// 隣が中央へ来て切り替わる。中央のタップで送信、隣のタップでその候補へ寄る、右上の
/// ×で一覧へ戻る。ぺったんの送信方法がLINE型の時だけ使う。
class StickerSuggestionPreview extends ConsumerStatefulWidget {
  const StickerSuggestionPreview({
    required this.stickers,
    required this.index,
    required this.onIndexChanged,
    required this.onSend,
    required this.onClose,
    super.key,
  });

  final List<Sticker> stickers;
  final int index;
  final void Function(int index) onIndexChanged;
  final void Function(Sticker sticker) onSend;
  final VoidCallback onClose;

  @override
  ConsumerState<StickerSuggestionPreview> createState() =>
      _StickerSuggestionPreviewState();
}

class _StickerSuggestionPreviewState
    extends ConsumerState<StickerSuggestionPreview> {
  static const _maxSize = 240.0;
  static const _verticalPadding = 12.0;
  static const _neighbourScale = 0.55;
  static const _neighbourOpacity = 0.45;

  PageController? _controller;
  double _fraction = 0;

  /// 中央のぺったんの幅に合わせて、隣が覗く`viewportFraction`でコントローラーを作る。
  /// 幅が変わった時だけ作り直す。
  PageController _ensureController(double fraction) {
    final current = _controller;
    if (current != null && (fraction - _fraction).abs() < 0.005) return current;
    _fraction = fraction;
    final next = PageController(
      initialPage: widget.index,
      viewportFraction: fraction,
    );
    _controller = next;
    if (current != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => current.dispose());
    }
    return next;
  }

  @override
  void didUpdateWidget(StickerSuggestionPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    final controller = _controller;
    // 外からの切り替えにページを追従させる。
    if (controller != null &&
        controller.hasClients &&
        controller.page?.round() != widget.index) {
      controller.animateToPage(
        widget.index,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isGekiga = ref.watch(appUiStyleProvider) == AppUiStyle.gekiga;
    final colorScheme = Theme.of(context).colorScheme;
    final iconColor = isGekiga ? GekigaColors.onPanel : colorScheme.onSurface;
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = math.min(
          constraints.maxHeight - _verticalPadding * 2,
          _maxSize,
        );
        // 隣が覗くよう、中央の幅より少し広い間隔でページを並べる。
        final fraction = constraints.maxWidth <= 0
            ? 1.0
            : ((size + 32) / constraints.maxWidth).clamp(0.3, 1.0);
        final controller = _ensureController(fraction);
        return Stack(
          children: [
            Positioned.fill(
              // マウスでも横にドラッグして切り替えられるようにする。
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(context).copyWith(
                  dragDevices: {
                    PointerDeviceKind.touch,
                    PointerDeviceKind.mouse,
                    PointerDeviceKind.trackpad,
                    PointerDeviceKind.stylus,
                  },
                ),
                child: PageView.builder(
                  controller: controller,
                  itemCount: widget.stickers.length,
                  onPageChanged: widget.onIndexChanged,
                  itemBuilder: (context, i) => AnimatedBuilder(
                    animation: controller,
                    builder: (context, child) {
                      final page =
                          controller.hasClients &&
                              controller.position.haveDimensions
                          ? (controller.page ?? widget.index.toDouble())
                          : widget.index.toDouble();
                      final delta = (page - i).abs().clamp(0.0, 1.0);
                      return Center(
                        child: Opacity(
                          opacity: 1 - (1 - _neighbourOpacity) * delta,
                          child: Transform.scale(
                            scale: 1 - (1 - _neighbourScale) * delta,
                            child: child,
                          ),
                        ),
                      );
                    },
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        if (i == widget.index) {
                          widget.onSend(widget.stickers[i]);
                        } else {
                          controller.animateToPage(
                            i,
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeOut,
                          );
                        }
                      },
                      child: SizedBox(
                        width: size,
                        height: size,
                        child: StickerImage(
                          widget.stickers[i].imageUrl,
                          fit: BoxFit.contain,
                          errorBuilder: (_, _, _) =>
                              const Icon(Icons.broken_image_outlined),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 2,
              right: 2,
              child: IconButton(
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                iconSize: 20,
                visualDensity: VisualDensity.compact,
                color: iconColor,
                icon: const Icon(Icons.close),
                onPressed: widget.onClose,
              ),
            ),
          ],
        );
      },
    );
  }
}
