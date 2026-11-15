import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

/// 共有の準備（ファイルの取得）中に、画面の上へ出す進捗のカード（2026-11-15）。
/// [task]に渡す`onProgress`で進み具合（0〜1、不定ならnull）を更新し、終わると消える。
/// 共有シートが開く前までが対象（シートが開いたら消える）。
Future<void> runWithShareProgress(
  BuildContext context, {
  required String label,
  required Future<void> Function(void Function(double? progress) onProgress)
  task,
}) async {
  final overlay = Overlay.maybeOf(context);
  final progress = ValueNotifier<double?>(null);
  OverlayEntry? entry;
  if (overlay != null) {
    entry = OverlayEntry(
      builder: (context) =>
          _ShareProgressCard(label: label, progress: progress),
    );
    overlay.insert(entry);
  }
  var removed = false;
  void remove() {
    if (removed) return;
    removed = true;
    entry?.remove();
  }

  try {
    await task((value) {
      progress.value = value;
      // 取得が終わったら（共有シートを開く前に）カードを消す。
      if (value != null && value >= 1) remove();
    });
  } finally {
    remove();
    progress.dispose();
  }
}

class _ShareProgressCard extends StatelessWidget {
  const _ShareProgressCard({required this.label, required this.progress});

  final String label;
  final ValueListenable<double?> progress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Center(
            child: Material(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(12),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 220, maxWidth: 320),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                  child: ValueListenableBuilder<double?>(
                    valueListenable: progress,
                    builder: (context, value, _) {
                      final percent = value == null
                          ? ''
                          : ' ${(value * 100).clamp(0, 100).round()}%';
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$label$percent',
                            style: TextStyle(color: scheme.onSurface),
                          ),
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: value,
                              color: scheme.onSurface,
                              backgroundColor: scheme.onSurface.withValues(
                                alpha: 0.15,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
