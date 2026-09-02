import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';
import '../../models/app_ui_style.dart';
import '../../models/sticker.dart';
import '../../providers/app_ui_style_provider.dart';
import '../../providers/repository_providers.dart';
import '../../utils/auto_dismiss_banner.dart';
import '../../widgets/glass/glass_dialog.dart';

/// 所持しているペタピタパック一覧・アンインストールのポップアップ（設定＞
/// アカウントから開く、2026-08-11追加。当初はページ遷移だったが、
/// `group_role_list_popup.dart`と同じ「ヘッダー＋区切り線＋中身」の
/// ダイアログ形式に変更）。`sticker_picker_sheet.dart`と同じ
/// `watchOwnedPacks`ストリームを購読するため、アンインストール後に
/// Firestore側の削除が伝播すればリストから自動的に消える（手動リフレッシュ不要）。
class OwnedStickerPacksPopup extends ConsumerWidget {
  const OwnedStickerPacksPopup({required this.userId, super.key});

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 4, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  strings.ownedStickersScreenTitle,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Flexible(
          child: StreamBuilder<List<StickerPack>>(
            stream: ref
                .watch(stickerRepositoryProvider)
                .watchOwnedPacks(userId),
            builder: (context, snapshot) {
              final packs = snapshot.data;
              if (packs == null) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (packs.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    strings.chatNoStickersMessage,
                    textAlign: TextAlign.center,
                  ),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: packs.length,
                separatorBuilder: (_, _) => const SizedBox(height: 16),
                itemBuilder: (context, index) =>
                    _OwnedPackCard(strings: strings, pack: packs[index]),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _OwnedPackCard extends ConsumerWidget {
  const _OwnedPackCard({required this.strings, required this.pack});

  final Strings strings;
  final StickerPack pack;

  Future<void> _uninstall(BuildContext context, WidgetRef ref) async {
    final isGlass = ref.read(appUiStyleProvider) == AppUiStyle.glass;
    final confirmed = await _confirmUninstall(context, strings, isGlass);
    if (!confirmed || !context.mounted) return;
    try {
      await ref.read(stickerRepositoryProvider).uninstallPack(pack.packId);
    } catch (e) {
      if (!context.mounted) return;
      showAutoDismissBanner(context, message: '$e');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    pack.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                TextButton(
                  onPressed: () => _uninstall(context, ref),
                  style: TextButton.styleFrom(
                    foregroundColor: colorScheme.error,
                  ),
                  child: Text(strings.uninstallStickerButton),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 64,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: pack.stickers.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final sticker = pack.stickers[index];
                  return SizedBox(
                    width: 64,
                    child: Image.network(
                      sticker.imageUrl,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) =>
                          const Icon(Icons.broken_image_outlined),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<bool> _confirmUninstall(
  BuildContext context,
  Strings strings,
  bool isGlass,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) {
      final title = Text(strings.uninstallStickerConfirmTitle);
      final content = Text(strings.uninstallStickerConfirmMessage);
      final actions = [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(strings.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(strings.uninstallStickerConfirmButton),
        ),
      ];
      return isGlass
          ? GlassAlertDialog(title: title, content: content, actions: actions)
          : AlertDialog(title: title, content: content, actions: actions);
    },
  );
  return confirmed ?? false;
}
