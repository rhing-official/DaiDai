import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../widgets/pane_key_focus.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../l10n/strings.dart';
import '../../models/album.dart';
import '../../models/album_item.dart';
import '../../models/app_ui_style.dart';
import '../../providers/app_ui_style_provider.dart';
import '../../providers/repository_providers.dart';
import '../../utils/attachment_upload.dart';
import '../../utils/auto_dismiss_banner.dart';
import '../../widgets/glass/glass_app_bar.dart';
import '../../widgets/glass/glass_dialog.dart';
import '../../widgets/swipe_gestures.dart';
import '../../widgets/press_drag_menu.dart';
import '../../widgets/upload_progress_bar.dart';
import '../../widgets/video_thumbnail.dart';
import '../../widgets/media_viewer_screen.dart';
import 'album_message_picker_screen.dart';
import '../../widgets/dialog_keyboard_shortcuts.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/pane_title_row_app_bar.dart';

/// 寄合単位の共有アルバムの中身を寄合の表示領域内で開く（2026-09-07、
/// `NotePaneView`/`CalendarPaneView`と同じ「ローカルなbool/オブジェクト
/// 切り替えで中身を差し替える」方式に変更。以前の`AlbumDetailScreen`は
/// `Navigator.push`によるフルスクリーン別ルート遷移だった為、ワイド画面の
/// 分割表示でフレンド/寄合一覧のサイドバーまで覆ってしまう不具合を抱えて
/// いた）。あわせて、画像・動画をギャラリーから直接アップロードする「＋」
/// ボタンを新設した（従来はメッセージ長押し→「アルバムに登録」で既存の
/// メッセージ添付をコピーする一方向のみだった）。
///
/// アルバム名の改名機能は2026-09-07に廃止した（ポップアップ一覧側の
/// 「︙」メニュー以外に手段が無かった為、そのメニュー自体をゴミ箱ボタン
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

  // dispose中は`ref`が使えない（Riverpod 3は例外を投げる）ので、名前の確定に使う
  // リポジトリは先に保持しておく。
  late final _albumRepository = ref.read(albumRepositoryProvider);

  bool _uploading = false;

  /// アルバム名の入力欄。閉じた時（[_close]・[dispose]）に確定する（2026-11-07）。
  /// 空欄で閉じた時は変更せず、元の名前のままにする。
  late final _nameController = TextEditingController(text: widget.album.name);

  /// 保存済みの（一覧に出ている）名前。
  late String _savedName = widget.album.name;

  /// アルバム自体を削除した後は、名前を保存し直さない。
  bool _deleted = false;

  /// アップロード進捗（0.0〜1.0）。アップロード中だけ非null（2026-11-07）。
  double? _uploadProgress;

  /// メッセージから追加する選択画面をこのペイン内に表示中か（2026-09-26
  /// 追加）。以前は`Navigator.push`のフルスクリーン別ルートで
  /// `AlbumMessagePickerScreen`を開いていたが、このクラス自身が
  /// `NotePaneView`/`CalendarPaneView`と同じ「サイドバーを覆わないローカル
  /// 状態切り替え」方式を採用している以上、内部で開くサブ画面も同じ方式に
  /// 揃える必要があった（CLAUDE.mdの「メッセージ画面の範囲内表示」の方針
  /// 参照）。
  bool _showingMessagePicker = false;

  /// 開いているアルバム自体を削除する（確認あり、中の画像・動画も全て消える。
  /// アルバム一覧の削除アイコン（`album_popup_content.dart`）と同じ文言・処理）。
  /// 削除できたらペインを閉じて一覧へ戻る（2026-11-07）。
  Future<void> _deleteAlbum() async {
    final strings = ref.read(appStringsProvider);
    final isGlass = ref.read(appUiStyleProvider) == AppUiStyle.glass;
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final title = Text(strings.albumDeleteConfirmTitle);
        final content = Text(strings.albumDeleteConfirmMessage);
        final actions = [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
            ),
            child: Text(strings.delete),
          ),
        ];
        return isGlass
            ? GlassAlertDialog(title: title, content: content, actions: actions)
            : KeyboardAlertDialog(
                title: title,
                content: content,
                actions: actions,
              );
      },
    );
    if (confirmed != true || !mounted) return;
    await ref
        .read(albumRepositoryProvider)
        .deleteAlbum(
          isDm: widget.isDm,
          conversationId: widget.conversationId,
          roomId: widget.roomId,
          albumId: widget.album.albumId,
        );
    if (mounted) widget.onClose();
  }

  Future<void> _removeItem(AlbumItem item) async {
    final strings = ref.read(appStringsProvider);
    final isGlass = ref.read(appUiStyleProvider) == AppUiStyle.glass;
    final confirmed = await showAppDialog<bool>(
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
            : KeyboardAlertDialog(
                title: title,
                content: content,
                actions: actions,
              );
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

  /// 「＋」ボタン（押したまま項目へなぞって離しても選べる[PressDragMenuButton]）から、
  /// 先ず追加元（端末／メッセージ）を選ぶ。「メッセージ
  /// から」はこのペイン内で[_showingMessagePicker]に切り替える（2026-09-26、
  /// 以前は`Navigator.push`のフルスクリーン別ルートだったが、
  /// `AlbumPaneView`自体の「サイドバーを覆わないローカル状態切り替え」
  /// 方式に揃えた）。「端末から」は`ImagePicker().pickMedia()`で画像/動画を
  /// 単一のOS標準ピッカーから選ばせる（2026-09-26、以前は独自の画像/動画
  /// 2択ポップアップを挟んでいたが、OS標準ピッカー自体が両方を一覧出来る
  /// ためユーザー指示で撤廃した。選ばれたファイルの種別は拡張子/mimeTypeで
  /// 事後判定する、`isVideoFileName`参照）。
  Future<void> _onAddSource(String source) async {
    if (!mounted) return;
    if (source == 'message') {
      setState(() => _showingMessagePicker = true);
      return;
    }

    // 一度に選べる数に上限は設けない（2026-11-07、以前は1つだけ）。
    final picked = await ImagePicker().pickMultipleMedia();
    if (picked.isEmpty) return;
    await _uploadAll(picked);
  }

  /// 選んだ画像・動画を、[_uploadConcurrency]件ずつ同時にアップロードして登録する。
  /// 進捗は全体の平均で出す。1件失敗しても残りは続け、最後に失敗を知らせる
  /// （登録できたものはそのまま残る）。
  static const _uploadConcurrency = 3;

  Future<void> _uploadAll(List<XFile> files) async {
    if (_uploading) return;
    setState(() {
      _uploading = true;
      _uploadProgress = 0;
    });
    final repository = ref.read(albumRepositoryProvider);
    final progress = List<double>.filled(files.length, 0);
    void report() {
      if (!mounted) return;
      setState(
        () => _uploadProgress =
            progress.fold<double>(0, (a, b) => a + b) / files.length,
      );
    }

    Object? firstError;
    var failed = 0;
    var next = 0;
    Future<void> worker() async {
      while (true) {
        final index = next++;
        if (index >= files.length) return;
        final file = files[index];
        try {
          final contentType =
              isVideoFileName(file.name, mimeType: file.mimeType)
              ? 'video'
              : 'image';
          // 大きい動画を全て同時にメモリへ載せない為、送る直前に読み込む。
          await repository.addItemFromUpload(
            isDm: widget.isDm,
            conversationId: widget.conversationId,
            roomId: widget.roomId,
            albumId: widget.album.albumId,
            bytes: await file.readAsBytes(),
            fileName: file.name,
            contentType: contentType,
            addedBy: widget.currentUserId,
            onProgress: (p) {
              progress[index] = p;
              report();
            },
          );
        } catch (e) {
          failed++;
          firstError ??= e;
        }
        progress[index] = 1;
        report();
      }
    }

    try {
      await Future.wait([
        for (var w = 0; w < math.min(_uploadConcurrency, files.length); w++)
          worker(),
      ]);
    } finally {
      if (mounted) {
        setState(() {
          _uploading = false;
          _uploadProgress = null;
        });
        if (failed > 0) {
          showAutoDismissBanner(
            context,
            message: files.length == 1
                ? '$firstError'
                : '$failed/${files.length}: $firstError',
          );
        }
      }
    }
  }

  /// 入力された名前を保存する。空欄（空白のみ）や変更なしなら何もしない
  /// （元の名前のまま）。
  Future<void> _commitName() async {
    final name = _nameController.text.trim();
    if (_deleted || name.isEmpty || name == _savedName) return;
    _savedName = name;
    await ref
        .read(albumRepositoryProvider)
        .renameAlbum(
          isDm: widget.isDm,
          conversationId: widget.conversationId,
          roomId: widget.roomId,
          albumId: widget.album.albumId,
          name: name,
        );
  }

  /// 名前を確定してから閉じる。
  Future<void> _close() async {
    FocusManager.instance.primaryFocus?.unfocus();
    try {
      await _commitName();
    } catch (_) {
      // 名前の保存に失敗しても閉じる（元の名前のまま）。
    }
    if (mounted) widget.onClose();
  }

  @override
  void initState() {
    super.initState();
    // dispose中に使えるよう、最初に取り出しておく。
    _albumRepository;
  }

  @override
  void dispose() {
    // 暗幕のタップなど[_close]を通らずに閉じられた場合も、名前を確定する。
    final name = _nameController.text.trim();
    if (!_deleted && name.isNotEmpty && name != _savedName) {
      _albumRepository
          .renameAlbum(
            isDm: widget.isDm,
            conversationId: widget.conversationId,
            roomId: widget.roomId,
            albumId: widget.album.albumId,
            name: name,
          )
          .catchError((_) {});
    }
    _nameController.dispose();
    super.dispose();
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

    // アルバム名（そのまま書き換えられる。空欄で閉じると元の名前に戻る）。
    final title = TextField(
      controller: _nameController,
      maxLength: 50,
      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
      decoration: const InputDecoration(
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        disabledBorder: InputBorder.none,
        filled: false,
        counterText: '',
        isCollapsed: true,
        contentPadding: EdgeInsets.symmetric(vertical: 12),
      ),
      onSubmitted: (_) => _commitName(),
    );
    final addAction = PressDragMenuButton<String>(
      enabled: !_uploading,
      onSelected: _onAddSource,
      items: [
        PressDragMenuItem(
          value: 'device',
          icon: Icons.smartphone_outlined,
          label: strings.albumAddSourceDeviceLabel,
        ),
        PressDragMenuItem(
          value: 'message',
          icon: Icons.forum_outlined,
          label: strings.albumAddSourceMessageLabel,
        ),
      ],
      child: IconButton(
        icon: _uploading
            ? const SizedBox.shrink()
            : const Icon(Icons.add_photo_alternate_outlined),
        tooltip: '',
        // 押下はPressDragMenuButton（Listener）が受ける。
        onPressed: _uploading ? null : () {},
      ),
    );

    final deleteAction = IconButton(
      icon: const Icon(Icons.delete_outline),
      tooltip: '',
      onPressed: _uploading ? null : _deleteAlbum,
    );

    // 幅が狭い（縦画面）時は、ボタンの行と題名の行を分ける（題名の文字サイズは縮めない）。
    return LayoutBuilder(
      builder: (context, constraints) {
        final twoRows = paneNeedsTitleRow(
          maxWidth: constraints.maxWidth,
          actionCount: 2,
          titleFontSize: 24,
          textScale: MediaQuery.textScalerOf(context).scale(1),
        );
        final bottom = twoRows
            ? paneTitleRowBottom(
                context: context,
                titleField: title,
                titleFontSize: 24,
              )
            : null;
        return Scaffold(
          appBar: isGlass
              ? GlassAppBar(
                  automaticallyImplyLeading: false,
                  title: twoRows ? null : title,
                  bottom: bottom,
                  actions: [addAction, deleteAction],
                )
              : AppBar(
                  automaticallyImplyLeading: false,
                  title: twoRows ? null : title,
                  bottom: bottom,
                  actions: [addAction, deleteAction],
                ),
          body: PaneKeyFocus(
            onKeyEvent: (node, event) {
              if (event is! KeyDownEvent) return KeyEventResult.ignored;
              if (event.logicalKey == LogicalKeyboardKey.escape) {
                _close();
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: SwipeDownToDismiss(
              onDismiss: _close,
              child: Column(
                children: [
                  if (_uploadProgress case final progress?)
                    UploadProgressBar(progress: progress),
                  Expanded(child: _itemsGrid(strings)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _itemsGrid(Strings strings) {
    return StreamBuilder<List<AlbumItem>>(
      stream: _itemsStream,
      builder: (context, snapshot) {
        final items = snapshot.data ?? const <AlbumItem>[];
        if (items.isEmpty) {
          return Center(child: Text(strings.albumListEmptyMessage));
        }
        return GridView.builder(
          padding: const EdgeInsets.all(4),
          // 1枚の大きさは最大約180px（2026-11-07、以前の110pxは小さすぎた）。
          // メッセージから追加する一覧と共通（[kAlbumTileMaxExtent]）。
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: kAlbumTileMaxExtent,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
          ),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            return GestureDetector(
              // メッセージ画面と同じビューア（矢印・ダウンロード・共有・動画
              // コントロール等）で開く（2026-11-02）。
              onTap: () => openMediaViewer(
                context,
                items: [
                  for (final i in items)
                    MediaViewerItem(
                      id: i.itemId,
                      url: i.url,
                      contentType: i.contentType,
                      thumbnailUrl: i.thumbnailUrl,
                      playbackUrl: i.playbackUrl,
                    ),
                ],
                initialIndex: index,
              ),
              onLongPress: () => _removeItem(item),
              child: item.contentType == 'video'
                  // タイルの大きさに合わせる（正方形）。サーバーが作ったサムネイルが
                  // あればそれを出す（無い間・古い動画は動画から先頭付近のコマ）。
                  ? LayoutBuilder(
                      builder: (context, constraints) => VideoThumbnail(
                        // 重い動画は軽い版から先頭のコマを取る（2026-11-08）。
                        url: item.playbackUrl ?? item.url,
                        thumbnailUrl: item.thumbnailUrl,
                        canLoad: videoPlaybackSupported,
                        size: constraints.maxWidth,
                      ),
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
    );
  }
}
