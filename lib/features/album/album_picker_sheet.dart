import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';
import '../../models/album.dart';
import '../../models/app_ui_style.dart';
import '../../models/message.dart';
import '../../providers/app_ui_style_provider.dart';
import '../../providers/repository_providers.dart';
import '../../widgets/glass/glass_dialog.dart';

/// メッセージ長押しメニューの「アルバムに登録」から開くボトムシート
/// （2026-08-30追加）。その寄合の既存アルバム一覧から選ぶか、その場で
/// 新規作成してすぐ登録する。成功/失敗のSnackBar表示までここで完結させる。
Future<void> showAlbumPickerSheet(
  BuildContext context, {
  required bool isDm,
  required String conversationId,
  required String roomId,
  required Message message,
  required String currentUserId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _AlbumPickerSheet(
      isDm: isDm,
      conversationId: conversationId,
      roomId: roomId,
      message: message,
      currentUserId: currentUserId,
    ),
  );
}

class _AlbumPickerSheet extends ConsumerStatefulWidget {
  const _AlbumPickerSheet({
    required this.isDm,
    required this.conversationId,
    required this.roomId,
    required this.message,
    required this.currentUserId,
  });

  final bool isDm;
  final String conversationId;
  final String roomId;
  final Message message;
  final String currentUserId;

  @override
  ConsumerState<_AlbumPickerSheet> createState() => _AlbumPickerSheetState();
}

class _AlbumPickerSheetState extends ConsumerState<_AlbumPickerSheet> {
  late final Stream<List<Album>> _albumsStream = ref
      .read(albumRepositoryProvider)
      .watchAlbums(
        isDm: widget.isDm,
        conversationId: widget.conversationId,
        roomId: widget.roomId,
      );

  bool _submitting = false;

  Future<void> _addTo(String albumId) async {
    if (_submitting) return;
    setState(() => _submitting = true);
    final strings = ref.read(appStringsProvider);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(albumRepositoryProvider)
          .addItemFromMessage(
            isDm: widget.isDm,
            conversationId: widget.conversationId,
            roomId: widget.roomId,
            albumId: albumId,
            message: widget.message,
            addedBy: widget.currentUserId,
          );
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(content: Text(strings.albumAddedSnackbarMessage)),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitting = false);
      messenger.showSnackBar(
        SnackBar(content: Text(strings.albumAddFailedSnackbarMessage)),
      );
    }
  }

  Future<void> _createAndAddTo() async {
    final strings = ref.read(appStringsProvider);
    final controller = TextEditingController();
    final isGlass = ref.read(appUiStyleProvider) == AppUiStyle.glass;
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        final title = Text(strings.albumCreateDialogTitle);
        final content = TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: strings.albumNameFieldHint),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value.trim()),
        );
        final actions = [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(strings.cancel),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: Text(strings.commonCreate),
          ),
        ];
        return isGlass
            ? GlassAlertDialog(title: title, content: content, actions: actions)
            : AlertDialog(title: title, content: content, actions: actions);
      },
    );
    if (name == null || name.isEmpty) return;
    final album = await ref
        .read(albumRepositoryProvider)
        .createAlbum(
          isDm: widget.isDm,
          conversationId: widget.conversationId,
          roomId: widget.roomId,
          name: name,
          createdBy: widget.currentUserId,
        );
    await _addTo(album.albumId);
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                strings.albumPickerTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.add),
              title: Text(strings.albumPickerCreateNewOption),
              enabled: !_submitting,
              onTap: _createAndAddTo,
            ),
            const Divider(height: 1),
            Flexible(
              child: StreamBuilder<List<Album>>(
                stream: _albumsStream,
                builder: (context, snapshot) {
                  final albums = snapshot.data ?? const <Album>[];
                  if (albums.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(strings.albumListEmptyMessage),
                    );
                  }
                  return ListView.builder(
                    shrinkWrap: true,
                    itemCount: albums.length,
                    itemBuilder: (context, index) {
                      final album = albums[index];
                      return ListTile(
                        leading: album.coverThumbnailUrl != null
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: Image.network(
                                  album.coverThumbnailUrl!,
                                  width: 40,
                                  height: 40,
                                  fit: BoxFit.cover,
                                ),
                              )
                            : const Icon(Icons.photo_library_outlined),
                        title: Text(album.name),
                        subtitle: Text(
                          strings.albumItemCountLabel(album.itemCount),
                        ),
                        enabled: !_submitting,
                        onTap: () => _addTo(album.albumId),
                      );
                    },
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
