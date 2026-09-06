import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../l10n/strings.dart';

/// 投票の選択肢に添付する画像・動画を選ぶボタン（2026-09-06追加、画像専用
/// だった選択肢添付を動画にも対応させる際に共通化）。タップすると「画像」/
/// 「動画」を選ぶメニューが開き（`chatAttachImage`/`chatAttachVideo`と同じ
/// 文言を再利用）、選択済みならその場でプレビュー（画像はサムネイル、動画は
/// アップロード前のためライブサムネイルを作らず動画アイコンのバッジ表示に
/// 留める）を表示する。`poll_form_dialog.dart`（作成時）・
/// `poll_detail_dialog.dart`（回答中の選択肢追加）の両方で使う。
class PollOptionMediaPickerButton extends StatelessWidget {
  const PollOptionMediaPickerButton({
    required this.strings,
    required this.mediaBytes,
    required this.mediaType,
    required this.onPick,
    this.enabled = true,
    super.key,
  });

  final Strings strings;
  final Uint8List? mediaBytes;

  /// 'image' | 'video' | null（未選択）。
  final String? mediaType;
  final void Function(bool video) onPick;
  final bool enabled;

  static const double _size = 56;

  @override
  Widget build(BuildContext context) {
    Widget preview;
    if (mediaType == 'image' && mediaBytes != null) {
      preview = ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.memory(
          mediaBytes!,
          width: _size,
          height: _size,
          fit: BoxFit.cover,
        ),
      );
    } else if (mediaType == 'video') {
      preview = Container(
        width: _size,
        height: _size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
        child: const Icon(Icons.videocam),
      );
    } else {
      preview = SizedBox(
        width: _size,
        height: _size,
        child: const Icon(Icons.add_photo_alternate_outlined),
      );
    }

    return PopupMenuButton<bool>(
      tooltip: '',
      enabled: enabled,
      onSelected: onPick,
      itemBuilder: (context) => [
        PopupMenuItem(value: false, child: Text(strings.chatAttachImage)),
        PopupMenuItem(value: true, child: Text(strings.chatAttachVideo)),
      ],
      child: preview,
    );
  }
}
