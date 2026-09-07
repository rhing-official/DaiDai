import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../l10n/strings.dart';
import '../../models/album.dart';
import '../../models/album_item.dart';
import '../../models/app_ui_style.dart';
import '../../providers/app_ui_style_provider.dart';
import '../../providers/repository_providers.dart';
import '../../theme/popup_surface_colors.dart';
import '../../widgets/glass/glass_app_bar.dart';
import '../../widgets/glass/glass_dialog.dart';
import '../../widgets/swipe_gestures.dart';
import '../../widgets/video_thumbnail.dart';
import 'album_media_viewer_screen.dart';

/// 寄合単位の共有アルバムの中身を寄合の表示領域内で開く（2026-09-07、
/// `NotePaneView`/`CalendarPaneView`と同じ「ローカルなbool/オブジェクト
/// 切り替えで中身を差し替える」方式に変更。以前の`AlbumDetailScreen`は
/// `Navigator.push`によるフルスクリーン別ルート遷移だったため、ワイド画面の
/// 分割表示でフレンド/寄合一覧のサイドバーまで覆ってしまう不具合を抱えて
/// いた）。あわせて、画像・動画をギャラリーから直接アップロードする「＋」
/// ボタンを新設した（従来はメッセージ長押し→「アルバムに登録」で既存の
/// メッセージ添付をコピーする一方向のみだった）。
///
/// アルバム名の改名機能は2026-09-07に廃止した（ポップアップ一覧側の
/// 「︙」メニュー以外に手段が無かったため、そのメニュー自体をゴミ箱ボタン
/// 直接配置に置き換えた際にあわせて削除、ユーザー指示）。そのためここでは
/// アルバム名を静的な`Text`として表示するのみで、編集は行えない。
class AlbumPaneView extends ConsumerStatefulWidget {
  const AlbumPaneView({
    required this.isDm,
    required this.conversationId,
    required this.roomId,
    required this.album,
    required this.currentUserId,
    required this.onClose,
    super.key,
  });

  final bool isDm;
  final String conversationId;
  final String roomId;
  final Album album;
  final String currentUserId;
  final VoidCallback onClose;

  @override
  ConsumerState<AlbumPaneView> createState() => _AlbumPaneViewState();
}

class _AlbumPaneViewState extends ConsumerState<AlbumPaneView> {
  late final Stream<List<AlbumItem>> _itemsStream = ref
      .read(albumRepositoryProvider)
      .watchItems(
        isDm: widget.isDm,
        conversationId: widget.conversationId,
        roomId: widget.roomId,
        albumId: widget.album.albumId,
      );

  bool _uploading = false;

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

  /// 添付選択肢のポップアップを開く（`note_pane_view.dart`の
  /// `_pickAndInsertAttachment`と同じ、ボタン直下にアンカーする
  /// `showMenu`+`RelativeRect`パターン。アルバムは画像・動画のみ対応する
  /// ため選択肢はファイルを含まない2択）。
  final _addButtonKey = GlobalKey();

  Future<void> _pickAndUpload() async {
    final strings = ref.read(appStringsProvider);
    final buttonContext = _addButtonKey.currentContext;
    if (buttonContext == null) return;
    final box = buttonContext.findRenderObject()! as RenderBox;
    final bottomLeft = box.localToGlobal(Offset(0, box.size.height));
    final bottomRight = box.localToGlobal(
      Offset(box.size.width, box.size.height),
    );
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(bottomLeft, bottomRight),
      Offset.zero & overlay.size,
    );
    final choice = await showMenu<String>(
      context: context,
      position: position,
      color: Colors.transparent,
      shadowColor: Colors.transparent,
      elevation: 0,
      items: [
        PopupMenuItem<String>(
          enabled: false,
          padding: EdgeInsets.zero,
          child: _AlbumAddPopupContent(strings: strings),
        ),
      ],
    );
    if (choice == null || !mounted) return;
    switch (choice) {
      case 'image':
        final picked = await ImagePicker().pickImage(
          source: ImageSource.gallery,
        );
        if (picked == null) return;
        await _upload(
          bytes: await picked.readAsBytes(),
          fileName: picked.name,
          contentType: 'image',
        );
      case 'video':
        final picked = await ImagePicker().pickVideo(
          source: ImageSource.gallery,
        );
        if (picked == null) return;
        await _upload(
          bytes: await picked.readAsBytes(),
          fileName: picked.name,
          contentType: 'video',
        );
    }
  }

  Future<void> _upload({
    required Uint8List bytes,
    required String fileName,
    required String contentType,
  }) async {
    if (_uploading) return;
    setState(() => _uploading = true);
    try {
      await ref
          .read(albumRepositoryProvider)
          .addItemFromUpload(
            isDm: widget.isDm,
            conversationId: widget.conversationId,
            roomId: widget.roomId,
            albumId: widget.album.albumId,
            bytes: bytes,
            fileName: fileName,
            contentType: contentType,
            addedBy: widget.currentUserId,
          );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final uiStyle = ref.watch(appUiStyleProvider);
    final isGlass = uiStyle == AppUiStyle.glass;

    final leadingButton = IconButton(
      icon: const Icon(Icons.arrow_back),
      tooltip: '',
      onPressed: widget.onClose,
    );
    final title = Text(widget.album.name);
    final addAction = IconButton(
      key: _addButtonKey,
      icon: _uploading
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.add_photo_alternate_outlined),
      tooltip: '',
      onPressed: _uploading ? null : _pickAndUpload,
    );

    return Scaffold(
      appBar: isGlass
          ? GlassAppBar(
              leading: leadingButton,
              title: title,
              actions: [addAction],
            )
          : AppBar(leading: leadingButton, title: title, actions: [addAction]),
      body: Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          if (event.logicalKey == LogicalKeyboardKey.escape) {
            widget.onClose();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: SwipeDownToDismiss(
          onDismiss: widget.onClose,
          child: StreamBuilder<List<AlbumItem>>(
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
        ),
      ),
    );
  }
}

/// 「＋」ボタンの選択肢ポップアップの中身。`note_pane_view.dart`の
/// `_AttachPopupContent`と同じ配色規約（`popup_surface_colors.dart`）に
/// 揃えた、画像/動画の2択リスト（アルバムはファイル添付を扱わないため
/// ノートと異なりファイルの項目は無い）。
class _AlbumAddPopupContent extends ConsumerWidget {
  const _AlbumAddPopupContent({required this.strings});

  final Strings strings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brightness = Theme.of(context).brightness;
    final uiStyle = ref.watch(appUiStyleProvider);
    final onInverse = popupCardForeground(brightness, uiStyle);

    Widget optionRow(IconData icon, String label, String value) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => Navigator.of(context).pop(value),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            child: Row(
              children: [
                Icon(icon, color: onInverse),
                const SizedBox(width: 12),
                Text(label, style: TextStyle(color: onInverse)),
              ],
            ),
          ),
        ),
      );
    }

    return SizedBox(
      width: 220,
      child: Container(
        decoration: BoxDecoration(
          color: popupCardBackground(brightness, uiStyle),
          border: Border.all(color: popupCardBorder(brightness, uiStyle)),
          borderRadius: BorderRadius.circular(16),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            optionRow(Icons.image_outlined, strings.chatAttachImage, 'image'),
            optionRow(
              Icons.videocam_outlined,
              strings.chatAttachVideo,
              'video',
            ),
          ],
        ),
      ),
    );
  }
}
