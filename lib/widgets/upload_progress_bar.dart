import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/strings.dart';

/// アップロード中の進捗バーと「アップロード中… 〇%」（2026-11-07）。メッセージ画面の
/// 添付送信中の表示（`chat_screen.dart`の`_uploadProgressIndicator`）と同じ見た目で、
/// アルバムへの追加でも使う。[progress]は0.0〜1.0（0の間は不確定の動き）。
class UploadProgressBar extends ConsumerWidget {
  const UploadProgressBar({required this.progress, super.key});

  final double progress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final percent = (progress * 100).clamp(0, 100).round();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            strings.chatAttachmentUploadingLabel(percent),
            style: const TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress > 0 ? progress : null,
              minHeight: 4,
            ),
          ),
        ],
      ),
    );
  }
}
