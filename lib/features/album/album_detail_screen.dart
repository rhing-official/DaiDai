import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';
import '../../models/album.dart';
import '../../models/album_item.dart';
import '../../models/app_ui_style.dart';
import '../../providers/app_ui_style_provider.dart';
import '../../providers/repository_providers.dart';
import '../../widgets/glass/glass_dialog.dart';
import '../../widgets/video_thumbnail.dart';
import 'album_media_viewer_screen.dart';

/// 寄合単位の共有アルバムの中身（画像・動画混在グリッド、2026-08-30追加）。
class AlbumDetailScreen extends ConsumerStatefulWidget {
  const AlbumDetailScreen({
    super.key,
    required this.isDm,
    required this.conversationId,
    required this.roomId,
    required this.album,
  });

  final bool isDm;
  final String conversationId;
  final String roomId;
  final Album album;

  @override
  ConsumerState<AlbumDetailScreen> createState() => _AlbumDetailScreenState();
}

class _AlbumDetailScreenState extends ConsumerState<AlbumDetailScreen> {
  late final Stream<List<AlbumItem>> _itemsStream = ref
      .read(albumRepositoryProvider)
      .watchItems(
        isDm: widget.isDm,
        conversationId: widget.conversationId,
        roomId: widget.roomId,
        albumId: widget.album.albumId,
      );

  Future<void> _removeItem(AlbumItem item) async {
    final strings = ref.read(appStringsProvider);
    final isGlass = ref.read(appUiStyleProvider) == AppUiStyle.glass;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) {
        final title = Text(strings.albumRemoveItemConfirmTitle);
        final content = Text(strings.albumRemoveItemConfirmMessage);
        final actions = [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
            ),
            child: Text(strings.delete),
          ),
        ];
        return isGlass
            ? GlassAlertDialog(title: title, content: content, actions: actions)
            : AlertDialog(title: title, content: content, actions: actions);
      },
    );
    if (confirmed != true) return;
    await ref
        .read(albumRepositoryProvider)
        .removeItem(
          isDm: widget.isDm,
          conversationId: widget.conversationId,
          roomId: widget.roomId,
          albumId: widget.album.albumId,
          itemId: item.itemId,
        );
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(widget.album.name)),
      body: StreamBuilder<List<AlbumItem>>(
        stream: _itemsStream,
        builder: (context, snapshot) {
          final items = snapshot.data ?? const <AlbumItem>[];
          if (items.isEmpty) {
            return Center(child: Text(strings.albumListEmptyMessage));
          }
          return GridView.builder(
            padding: const EdgeInsets.all(4),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
            ),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return GestureDetector(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => AlbumMediaViewerScreen(
                      items: items,
                      initialIndex: index,
                    ),
                  ),
                ),
                onLongPress: () => _removeItem(item),
                child: item.contentType == 'video'
                    ? VideoThumbnail(
                        url: item.url,
                        canLoad: videoPlaybackSupported,
                        size: 120,
                      )
                    : Image.network(
                        item.url,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) =>
                            const ColoredBox(color: Colors.black12),
                      ),
              );
            },
          );
        },
      ),
    );
  }
}
