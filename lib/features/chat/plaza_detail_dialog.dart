import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';
import '../../l10n/vocabulary.dart';
import '../../models/group.dart';

/// 広場の詳細（`docs/マップ.md`の広場サイトマップ）を表示するダイアログ。
/// 現在実際に動いている構造（裏広場・単一の寄合のみ）と、まだ実装されていない
/// 表広場・表組/裏組・密談・談論をあわせて示す。データモデル自体に
/// `isPublic`や複数お部屋・カテゴリの概念がまだ無いため（CLAUDE.md記載の
/// フェーズ3項目）、ここでは「今のこの広場はどちらか」を固定表示しつつ、
/// 未実装の階層は準備中として案内するに留める。
class PlazaDetailDialog extends ConsumerWidget {
  const PlazaDetailDialog({required this.group, super.key});

  final Group group;

  static Future<void> show(BuildContext context, Group group) {
    return showDialog<void>(
      context: context,
      builder: (_) => PlazaDetailDialog(group: group),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final vocab = ref.watch(vocabularyProvider);

    return AlertDialog(
      title: Text(group.name),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _StatusRow(
                label: vocab.privatePlaza,
                subtitle: strings.plazaCurrentTypeSubtitle,
                implemented: true,
              ),
              const Divider(height: 24),
              _StatusRow(
                label: vocab.textChannel,
                subtitle: strings.plazaTextChannelSubtitle,
                implemented: true,
              ),
              _StatusRow(label: vocab.privateChannel, implemented: false),
              _StatusRow(label: vocab.category, implemented: false),
              _StatusRow(label: vocab.privateCategory, implemented: false),
              _StatusRow(label: vocab.projectBoard, implemented: false),
              const Divider(height: 24),
              _StatusRow(
                label: vocab.publicPlaza,
                subtitle: strings.plazaPublicPlazaSubtitle,
                implemented: false,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.cancel),
        ),
      ],
    );
  }
}

class _StatusRow extends ConsumerWidget {
  const _StatusRow({required this.label, this.subtitle, required this.implemented});

  final String label;
  final String? subtitle;
  final bool implemented;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            implemented ? Icons.check_circle_outline : Icons.schedule,
            size: 18,
            color: implemented ? colorScheme.primary : colorScheme.outline,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(
                  subtitle ?? strings.settingsComingSoon,
                  style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
