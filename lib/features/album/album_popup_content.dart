import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';
import '../../models/album.dart';
import '../../models/app_ui_style.dart';
import '../../providers/app_ui_style_provider.dart';
import '../../providers/repository_providers.dart';
import '../../theme/popup_surface_colors.dart';
import '../../widgets/glass/glass_dialog.dart';
import '../../widgets/glass/glass_surface.dart';

/// アルバムボタンの真下にアルバム一覧をポップアップ表示する（2026-08-30、
/// `chat_screen.dart`のピン留めポップアップ（`_openPinnedMessagesPopup`/
/// `_PinnedMessagesPopupContent`）と同じ構成に合わせた、ユーザー指示による
/// 変更）。フルスクリーン遷移だった`AlbumListScreen`を置き換え、位置計算
/// 済みの[position]の元で`showMenu`を開き、選ばれたアルバムを返す
/// （呼び出し元がそれを使って`AlbumDetailScreen`へ遷移する）。
Future<Album?> showAlbumPopup(
  BuildContext context, {
  required RelativeRect position,
  required bool isDm,
  required String conversationId,
  required String roomId,
  required String currentUserId,
}) {
  return showMenu<Album>(
    context: context,
    position: position,
    color: Colors.transparent,
    shadowColor: Colors.transparent,
    elevation: 0,
    items: [
      PopupMenuItem<Album>(
        enabled: false,
        padding: EdgeInsets.zero,
        child: _AlbumPopupContent(
          isDm: isDm,
          conversationId: conversationId,
          roomId: roomId,
          currentUserId: currentUserId,
        ),
      ),
    ],
  );
}

class _AlbumPopupContent extends ConsumerStatefulWidget {
  const _AlbumPopupContent({
    required this.isDm,
    required this.conversationId,
    required this.roomId,
    required this.currentUserId,
  });

  final bool isDm;
  final String conversationId;
  final String roomId;
  final String currentUserId;

  @override
  ConsumerState<_AlbumPopupContent> createState() => _AlbumPopupContentState();
}

class _AlbumPopupContentState extends ConsumerState<_AlbumPopupContent> {
  late final Stream<List<Album>> _albumsStream = ref
      .read(albumRepositoryProvider)
      .watchAlbums(
        isDm: widget.isDm,
        conversationId: widget.conversationId,
        roomId: widget.roomId,
      );

  Future<void> _createAlbum() async {
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
    await ref
        .read(albumRepositoryProvider)
        .createAlbum(
          isDm: widget.isDm,
          conversationId: widget.conversationId,
          roomId: widget.roomId,
          name: name,
          createdBy: widget.currentUserId,
        );
  }

  Future<void> _renameAlbum(Album album) async {
    final strings = ref.read(appStringsProvider);
    final controller = TextEditingController(text: album.name);
    final isGlass = ref.read(appUiStyleProvider) == AppUiStyle.glass;
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        final title = Text(strings.albumRenameDialogTitle);
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
            child: Text(strings.save),
          ),
        ];
        return isGlass
            ? GlassAlertDialog(title: title, content: content, actions: actions)
            : AlertDialog(title: title, content: content, actions: actions);
      },
    );
    if (name == null || name.isEmpty || name == album.name) return;
    await ref
        .read(albumRepositoryProvider)
        .renameAlbum(
          isDm: widget.isDm,
          conversationId: widget.conversationId,
          roomId: widget.roomId,
          albumId: album.albumId,
          newName: name,
        );
  }

  Future<void> _deleteAlbum(Album album) async {
    final strings = ref.read(appStringsProvider);
    final isGlass = ref.read(appUiStyleProvider) == AppUiStyle.glass;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) {
        final title = Text(strings.albumDeleteConfirmTitle);
        final content = Text(strings.albumDeleteConfirmMessage);
        final actions = [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            // colorScheme.errorはダークテーマ下でコントラストが不十分に
            // なるため固定の濃い赤にする（CLAUDE.md記載の既存の教訓）。
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
        .deleteAlbum(
          isDm: widget.isDm,
          conversationId: widget.conversationId,
          roomId: widget.roomId,
          albumId: album.albumId,
        );
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final brightness = Theme.of(context).brightness;
    final uiStyle = ref.watch(appUiStyleProvider);
    final onInverse = popupCardForeground(brightness, uiStyle);

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.photo_library_outlined, size: 16, color: onInverse),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                strings.albumListTitle,
                style: TextStyle(color: onInverse, fontWeight: FontWeight.bold),
              ),
            ),
            IconButton(
              icon: Icon(Icons.add, size: 20, color: onInverse),
              tooltip: '',
              onPressed: _createAlbum,
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
        const SizedBox(height: 8),
        StreamBuilder<List<Album>>(
          stream: _albumsStream,
          builder: (context, snapshot) {
            final albums = snapshot.data ?? const <Album>[];
            if (albums.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  strings.albumListEmptyMessage,
                  style: TextStyle(color: onInverse),
                ),
              );
            }
            return ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final album in albums)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _AlbumPopupCard(
                          album: album,
                          uiStyle: uiStyle,
                          strings: strings,
                          onTap: () => Navigator.of(context).pop(album),
                          onRename: () => _renameAlbum(album),
                          onDelete: () => _deleteAlbum(album),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );

    final padded = Padding(padding: const EdgeInsets.all(12), child: content);

    return SizedBox(
      width: 300,
      child: Container(
        decoration: BoxDecoration(
          color: popupCardBackground(brightness, uiStyle),
          border: Border.all(color: popupCardBorder(brightness, uiStyle)),
          borderRadius: BorderRadius.circular(16),
        ),
        child: padded,
      ),
    );
  }
}

enum _AlbumCardAction { rename, delete }

/// ポップアップ内のアルバム1件分のカード。`_PinnedMessageCard`
/// （`chat_screen.dart`）と同じ見た目の構成（カード本体タップで選択・
/// 右上に操作メニュー）。
class _AlbumPopupCard extends StatelessWidget {
  const _AlbumPopupCard({
    required this.album,
    required this.uiStyle,
    required this.strings,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
  });

  final Album album;
  final AppUiStyle uiStyle;
  final Strings strings;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final isGlass = uiStyle == AppUiStyle.glass;
    final brightness = Theme.of(context).brightness;
    final onInverse = popupCardForeground(brightness, uiStyle);
    final coverUrl = album.coverThumbnailUrl;

    final body = Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 40, 10),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: coverUrl != null
                ? Image.network(
                    coverUrl,
                    width: 40,
                    height: 40,
                    fit: BoxFit.cover,
                  )
                : Container(
                    width: 40,
                    height: 40,
                    color: onInverse.withValues(alpha: 0.12),
                    child: Icon(Icons.photo_library_outlined, color: onInverse),
                  ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  album.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: onInverse,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  strings.albumItemCountLabel(album.itemCount),
                  style: TextStyle(
                    color: onInverse.withValues(alpha: 0.7),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    final card = isGlass
        ? GlassSurface(
            variant: GlassVariant.card,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onTap,
              child: body,
            ),
          )
        : Material(
            color: onInverse.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onTap,
              child: body,
            ),
          );

    return Stack(
      children: [
        card,
        Positioned(
          top: 4,
          right: 4,
          child: PopupMenuButton<_AlbumCardAction>(
            icon: Icon(Icons.more_vert, size: 18, color: onInverse),
            padding: EdgeInsets.zero,
            onSelected: (action) {
              switch (action) {
                case _AlbumCardAction.rename:
                  onRename();
                case _AlbumCardAction.delete:
                  onDelete();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: _AlbumCardAction.rename,
                child: Text(strings.albumRenameAction),
              ),
              PopupMenuItem(
                value: _AlbumCardAction.delete,
                child: Text(strings.albumDeleteAction),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
