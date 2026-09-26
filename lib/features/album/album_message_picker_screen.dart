import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';
import '../../models/app_ui_style.dart';
import '../../models/message.dart';
import '../../providers/app_ui_style_provider.dart';
import '../../providers/repository_providers.dart';
import '../../widgets/glass/glass_app_bar.dart';
import '../../widgets/swipe_gestures.dart';
import '../../widgets/video_thumbnail.dart';

/// アルバムへ「メッセージから追加」する際の選択画面（2026-09-26追加）。
/// その寄合（roomId）に投稿された画像・動画メッセージ（`AlbumRepository.
/// watchMediaMessages`）をグリッドで一覧し、複数選択して一括でアルバムへ
/// 登録する。既存の「メッセージ長押し→アルバムに登録」
/// （`album_picker_sheet.dart`、メッセージ側からアルバムを選ぶ）とは逆方向の
/// 導線（アルバム側から過去メッセージを選ぶ）。
///
/// `AlbumPaneView`と同じ「ローカル状態切り替えでペイン内容を差し替える」
/// 方式で表示するため、`Navigator.push`は行わずこのウィジェット自身が
/// 語らい画面の表示領域内に収まる（2026-09-26、当初`Navigator.push`の
/// フルスクリーン別ルートで実装していたが、`AlbumPaneView`のドキュメント
/// コメントが明記する「サイドバーまで覆ってしまう」不具合を再発させていた
/// ため修正。CLAUDE.mdの「メッセージ画面の範囲内表示」の方針参照）。
/// 閉じる操作（戻る・下スワイプ・追加確定後）はすべて[onClose]経由で
/// 呼び出し元に委ねる。
class AlbumMessagePickerScreen extends ConsumerStatefulWidget {
  const AlbumMessagePickerScreen({
    required this.isDm,
    required this.conversationId,
    required this.roomId,
    required this.albumId,
    required this.currentUserId,
    required this.onClose,
    super.key,
  });

  final bool isDm;
  final String conversationId;
  final String roomId;
  final String albumId;
  final String currentUserId;
  final VoidCallback onClose;

  @override
  ConsumerState<AlbumMessagePickerScreen> createState() =>
      _AlbumMessagePickerScreenState();
}

class _AlbumMessagePickerScreenState
    extends ConsumerState<AlbumMessagePickerScreen> {
  late final Stream<List<Message>> _messagesStream = ref
      .read(albumRepositoryProvider)
      .watchMediaMessages(
        isDm: widget.isDm,
        conversationId: widget.conversationId,
        roomId: widget.roomId,
      );

  final _selected = <String>{};
  bool _submitting = false;

  void _toggle(Message message) {
    setState(() {
      if (!_selected.remove(message.messageId)) {
        _selected.add(message.messageId);
      }
    });
  }

  Future<void> _confirm(List<Message> messages) async {
    if (_selected.isEmpty || _submitting) return;
    setState(() => _submitting = true);
    final strings = ref.read(appStringsProvider);
    final messenger = ScaffoldMessenger.of(context);
    final repository = ref.read(albumRepositoryProvider);
    try {
      for (final message in messages) {
        if (!_selected.contains(message.messageId)) continue;
        await repository.addItemFromMessage(
          isDm: widget.isDm,
          conversationId: widget.conversationId,
          roomId: widget.roomId,
          albumId: widget.albumId,
          message: message,
          addedBy: widget.currentUserId,
        );
      }
      widget.onClose();
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

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final isGlass = ref.watch(appUiStyleProvider) == AppUiStyle.glass;

    return StreamBuilder<List<Message>>(
      stream: _messagesStream,
      builder: (context, snapshot) {
        // hiddenForに自分のuserIdを含むメッセージ（範囲選択削除で自分が
        // 消した分）は、他の一覧箇所（`talks_search.dart`等）と同じ慣習で
        // クライアント側フィルタして表示しない。
        final messages = (snapshot.data ?? const <Message>[])
            .where((m) => !m.hiddenFor.contains(widget.currentUserId))
            .toList();

        final title = Text(strings.albumMessagePickerTitle);
        final leadingButton = IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: '',
          onPressed: widget.onClose,
        );
        final confirmAction = TextButton(
          onPressed: _selected.isEmpty || _submitting
              ? null
              : () => _confirm(messages),
          child: Text(
            _selected.isEmpty
                ? strings.done
                : '${strings.done}'
                      '（${strings.albumItemCountLabel(_selected.length)}）',
          ),
        );

        return Scaffold(
          appBar: isGlass
              ? GlassAppBar(
                  leading: leadingButton,
                  title: title,
                  actions: [confirmAction],
                )
              : AppBar(
                  leading: leadingButton,
                  title: title,
                  actions: [confirmAction],
                ),
          body: SwipeDownToDismiss(
            onDismiss: widget.onClose,
            child: messages.isEmpty
                ? Center(child: Text(strings.albumMessagePickerEmptyMessage))
                : GridView.builder(
                    padding: const EdgeInsets.all(4),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          mainAxisSpacing: 4,
                          crossAxisSpacing: 4,
                        ),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final message = messages[index];
                      final url = message.fileMetadata?.url;
                      if (url == null) return const SizedBox.shrink();
                      final selected = _selected.contains(message.messageId);
                      return GestureDetector(
                        onTap: () => _toggle(message),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            message.contentType == 'video'
                                ? VideoThumbnail(
                                    url: url,
                                    canLoad: videoPlaybackSupported,
                                    size: 120,
                                  )
                                : Image.network(
                                    url,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) =>
                                        const ColoredBox(color: Colors.black12),
                                  ),
                            if (selected)
                              Container(
                                color: Colors.black38,
                                child: const Center(
                                  child: Icon(
                                    Icons.check_circle,
                                    color: Colors.white,
                                    size: 32,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        );
      },
    );
  }
}
