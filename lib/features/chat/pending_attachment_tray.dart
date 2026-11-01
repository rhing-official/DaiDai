import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../widgets/blurred_viewer_route.dart';
import '../../widgets/media_viewer_screen.dart';
import 'attachment_popup_button.dart';

/// 送信前の添付のトレイ（2026-10-31追加）。画像・動画・撮影で選んだものは、すぐ送らず
/// 入力欄の上の吹き出しにサムネイルで並べ、×で外す・タップで拡大（画像のみ）
/// ができる。送るのは入力欄の送信ボタン・送信キー（Enter等）で、トレイが先、入力欄の文字が
/// 後の別メッセージになる。
class PendingAttachmentTray extends StatelessWidget {
  const PendingAttachmentTray({
    required this.attachments,
    required this.strings,
    required this.onRemove,
    this.enabled = true,
    this.isGekiga = false,
    this.isGlass = false,
    this.onViewerClosed,
    super.key,
  });

  final List<PickedAttachment> attachments;
  final Strings strings;
  final ValueChanged<int> onRemove;

  /// 送信中などで操作できない間はfalse。
  final bool enabled;

  /// 劇画スタイルは、呼び出し側が手描き風の白い箱（入力欄と同じ）で包むため、ここでは
  /// 面を描かず、文字を黒にする。
  final bool isGekiga;

  /// ガラススタイルは、トレイ自身の面を持たずサムネイルだけを並べる。
  final bool isGlass;

  /// 拡大ビューアを閉じた時（入力欄へフォーカスを戻すため）。
  final VoidCallback? onViewerClosed;

  static const double _thumbSize = 96;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final borderColor = isGekiga ? Colors.black : colorScheme.outlineVariant;
    final list = SizedBox(
      height: _thumbSize + 8,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: attachments.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) => _Thumb(
          attachment: attachments[index],
          size: _thumbSize,
          borderColor: borderColor,
          removeTooltip: strings.chatPendingTrayRemoveTooltip,
          onRemove: enabled ? () => onRemove(index) : null,
          onOpen: attachments[index].contentType == 'image'
              ? () => _openViewer(context, index)
              : null,
        ),
      ),
    );
    if (isGekiga) return list;
    // フラット・ガラスは、トレイ自身の面を持たずサムネイルだけを並べる（入力欄エリアの
    // 背景がそのまま背景になる。ガラスは不透明な面を重ねると透け感が消える、2026-11-01）。
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: list,
    );
  }

  /// 画像だけを順にめくって拡大して見る（動画は拡大に対応しない）。
  void _openViewer(BuildContext context, int index) {
    final images = [
      for (final a in attachments)
        if (a.contentType == 'image') a,
    ];
    final initial = images.indexOf(attachments[index]);
    // メッセージ画面から開いた時と同じビューア（[MediaViewerScreen]）を使う。
    Navigator.of(context)
        .push(
          blurredViewerRoute(
            (_) => MediaViewerScreen(
              items: [
                for (var i = 0; i < images.length; i++)
                  MediaViewerItem(
                    id: 'pending-$i',
                    url: '',
                    contentType: 'image',
                    fileName: images[i].fileName,
                    bytes: images[i].bytes,
                  ),
              ],
              initialIndex: initial < 0 ? 0 : initial,
            ),
          ),
        )
        .then((_) => onViewerClosed?.call());
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({
    required this.attachment,
    required this.size,
    required this.borderColor,
    required this.removeTooltip,
    required this.onRemove,
    required this.onOpen,
  });

  final PickedAttachment attachment;
  final double size;
  final Color borderColor;
  final String removeTooltip;
  final VoidCallback? onRemove;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isImage = attachment.contentType == 'image';
    return SizedBox(
      width: size + 8,
      height: size + 8,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            bottom: 0,
            width: size,
            height: size,
            child: GestureDetector(
              onTap: onOpen,
              child: DecoratedBox(
                position: DecorationPosition.foreground,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: borderColor),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: isImage
                      ? Image.memory(
                          attachment.bytes,
                          fit: BoxFit.cover,
                          cacheWidth: (size * 2).round(),
                          errorBuilder: (_, _, _) => _placeholder(colorScheme),
                        )
                      : _placeholder(colorScheme, video: true),
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            width: 24,
            height: 24,
            child: Semantics(
              button: true,
              label: removeTooltip,
              child: GestureDetector(
                onTap: onRemove,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white70),
                  ),
                  child: const Icon(Icons.close, size: 14, color: Colors.white),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _placeholder(ColorScheme colorScheme, {bool video = false}) {
    return ColoredBox(
      color: colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          video ? Icons.play_circle_outline : Icons.image_outlined,
          color: colorScheme.onSurfaceVariant,
          size: 28,
        ),
      ),
    );
  }
}
