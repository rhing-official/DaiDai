import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../widgets/press_drag_menu.dart';

/// 投票の選択肢に添付する画像・動画を選ぶボタン（2026-09-06追加、画像専用
/// だった選択肢添付を動画にも対応させる際に共通化）。押すと即座に（長押し
/// 不要）ボタンの直下に、左端にアイコンの付いた「画像」/「動画」の2択が
/// プルダウンで開き、指を触れたまま滑らせて選ぶ・又は個別にタップして選べる
/// （2026-11-08変更、以前はボタンの右上に出る文字だけの2択だった。アルバムの
/// 「＋」と同じ共通部品[PressDragMenuButton]に置き換えた）。
/// 選択済みならその場でプレビュー（画像はサムネイル、動画はアップロード前の
/// ためライブサムネイルを作らず動画アイコンのバッジ表示に留める）を表示する。
/// `poll_form_dialog.dart`（作成時）・`poll_detail_dialog.dart`（回答中の
/// 選択肢追加）の両方で使う。
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
    final bytes = mediaBytes;
    Widget preview;
    if (mediaType == 'image' && bytes != null) {
      preview = ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.memory(
          bytes,
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

    return PressDragMenuButton<bool>(
      enabled: enabled,
      menuWidth: 160,
      items: [
        PressDragMenuItem(
          value: false,
          icon: Icons.image_outlined,
          label: strings.chatAttachImage,
        ),
        PressDragMenuItem(
          value: true,
          icon: Icons.videocam_outlined,
          label: strings.chatAttachVideo,
        ),
      ],
      onSelected: onPick,
      child: preview,
    );
  }
}
