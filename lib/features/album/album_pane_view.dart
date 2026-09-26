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
import '../../utils/attachment_upload.dart';
import '../../widgets/glass/glass_app_bar.dart';
import '../../widgets/glass/glass_dialog.dart';
import '../../widgets/swipe_gestures.dart';
import '../../widgets/video_thumbnail.dart';
import 'album_media_viewer_screen.dart';
import 'album_message_picker_screen.dart';

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

  /// メッセージから追加する選択画面をこのペイン内に表示中か（2026-09-26
  /// 追加）。以前は`Navigator.push`のフルスクリーン別ルートで
  /// `AlbumMessagePickerScreen`を開いていたが、このクラス自身が
  /// `NotePaneView`/`CalendarPaneView`と同じ「サイドバーを覆わないローカル
  /// 状態切り替え」方式を採用している以上、内部で開くサブ画面も同じ方式に
  /// 揃える必要があった（CLAUDE.mdの「メッセージ画面の範囲内表示」の方針
  /// 参照）。
  bool _showingMessagePicker = false;

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

  /// [_addButtonKey]の直下にポップアップをアンカーするための位置を計算する。
  /// 「端末から」／「メッセージから」の1段目と、「端末から」を選んだ後の
  /// 画像/動画の2段目、どちらも同じ位置に表示するため共通化した
  /// （2026-09-26追加）。
  RelativeRect? _addMenuPosition() {
    final buttonContext = _addButtonKey.currentContext;
    if (buttonContext == null) return null;
    final box = buttonContext.findRenderObject()! as RenderBox;
    final bottomLeft = box.localToGlobal(Offset(0, box.size.height));
    final bottomRight = box.localToGlobal(
      Offset(box.size.width, box.size.height),
    );
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    return RelativeRect.fromRect(
      Rect.fromPoints(bottomLeft, bottomRight),
      Offset.zero & overlay.size,
    );
  }

  /// 「＋」ボタンから、まず追加元（端末／メッセージ）を選ぶ。「メッセージ
  /// から」はこのペイン内で[_showingMessagePicker]に切り替える（2026-09-26、
  /// 以前は`Navigator.push`のフルスクリーン別ルートだったが、
  /// `AlbumPaneView`自体の「サイドバーを覆わないローカル状態切り替え」
  /// 方式に揃えた）。「端末から」は`ImagePicker().pickMedia()`で画像/動画を
  /// 単一のOS標準ピッカーから選ばせる（2026-09-26、以前は独自の画像/動画
  /// 2択ポップアップを挟んでいたが、OS標準ピッカー自体が両方を一覧できる
  /// ためユーザー指示で撤廃した。選ばれたファイルの種別は拡張子/mimeTypeで
  /// 事後判定する、`isVideoFileName`参照）。
  Future<void> _pickAndUpload() async {
    final strings = ref.read(appStringsProvider);
    final position = _addMenuPosition();
    if (position == null) return;
    final source = await showMenu<String>(
      context: context,
      position: position,
      color: Colors.transparent,
      shadowColor: Colors.transparent,
      elevation: 0,
      items: [
        PopupMenuItem<String>(
          enabled: false,
          padding: EdgeInsets.zero,
          child: _AlbumAddSourcePopupContent(strings: strings),
        ),
      ],
    );
    if (source == null || !mounted) return;
    if (source == 'message') {
      setState(() => _showingMessagePicker = true);
      return;
    }

    final picked = await ImagePicker().pickMedia();
    if (picked == null) return;
    final contentType = isVideoFileName(picked.name, mimeType: picked.mimeType)
        ? 'video'
        : 'image';
    await _upload(
      bytes: await picked.readAsBytes(),
      fileName: picked.name,
      contentType: contentType,
    );
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
    if (_showingMessagePicker) {
      return AlbumMessagePickerScreen(
        isDm: widget.isDm,
        conversationId: widget.conversationId,
        roomId: widget.roomId,
        albumId: widget.album.albumId,
        currentUserId: widget.currentUserId,
        onClose: () => setState(() => _showingMessagePicker = false),
      );
    }

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
          ? const SizedBox.shrink()
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

/// 「＋」ボタンをタップした最初の1段目、追加元（端末／メッセージ）の2択
/// ポップアップ（2026-09-26追加）。「端末」を選ぶと従来通り
/// [_AlbumAddPopupContent]（画像/動画の2択）へ進む。
class _AlbumAddSourcePopupContent extends ConsumerWidget {
  const _AlbumAddSourcePopupContent({required this.strings});

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
            optionRow(
              Icons.smartphone_outlined,
              strings.albumAddSourceDeviceLabel,
              'device',
            ),
            optionRow(
              Icons.forum_outlined,
              strings.albumAddSourceMessageLabel,
              'message',
            ),
          ],
        ),
      ),
    );
  }
}
