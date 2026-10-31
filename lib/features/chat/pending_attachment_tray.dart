import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../widgets/blurred_viewer_route.dart';
import '../../widgets/media_viewer_screen.dart';
import 'attachment_popup_button.dart';

/// 送信前の添付のトレイ（2026-10-31追加）。画像・動画・撮影で選んだものは、すぐ送らず
/// 入力欄の上の吹き出しにサムネイル＋ファイル名で並べ、×で外す・タップで拡大（画像のみ）
/// ができる。送るのは入力欄の送信ボタン・送信キー（Enter等）で、トレイが先、入力欄の文字が
/// 後の別メッセージになる。
class PendingAttachmentTray extends StatelessWidget {
  const PendingAttachmentTray({
    required this.attachments,
    required this.strings,
    required this.onRemove,
    this.enabled = true,
    this.isGekiga = false,
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

  static const double _thumbSize = 96;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final borderColor = isGekiga ? Colors.black : colorScheme.outlineVariant;
    final textColor = isGekiga ? Colors.black : colorScheme.onSurface;
    final list = SizedBox(
      height: _thumbSize + 8 + 20,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: attachments.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) => _Thumb(
          attachment: attachments[index],
          size: _thumbSize,
          borderColor: borderColor,
          textColor: textColor,
          removeTooltip: strings.chatPendingTrayRemoveTooltip,
          onRemove: enabled ? () => onRemove(index) : null,
          onOpen: attachments[index].contentType == 'image'
              ? () => _openViewer(context, index)
              : null,
        ),
      ),
    );
    if (isGekiga) return list;
    // 入力欄と同じ丸み（20）の吹き出しにして、背景（ガラスの透け等）に溶けないようにする。
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor),
      ),
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
    Navigator.of(context).push(
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
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({
    required this.attachment,
    required this.size,
    required this.borderColor,
    required this.textColor,
    required this.removeTooltip,
    required this.onRemove,
    required this.onOpen,
  });

  final PickedAttachment attachment;
  final double size;
  final Color borderColor;
  final Color textColor;
  final String removeTooltip;
  final VoidCallback? onRemove;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isImage = attachment.contentType == 'image';
    return SizedBox(
      width: size + 8,
      height: size + 8 + 20,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            bottom: 20,
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
            left: 0,
            bottom: 0,
            width: size,
            height: 18,
            child: Text(
              attachment.fileName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: textColor, fontSize: 11),
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
