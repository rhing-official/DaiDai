import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:provider/provider.dart' as provider;

import '../../../widgets/video_thumbnail.dart';

/// 動画のプレビューブロック（2026-11-15追加）。先頭のコマと再生アイコンを出し、
/// タップするとメッセージと同じ全画面ビューアで再生する。
class VideoEmbedBlockKeys {
  const VideoEmbedBlockKeys._();

  static const String type = 'video_embed';
  static const String url = 'url';
  static const String fileName = 'file_name';
}

Node videoEmbedNode({required String url, required String fileName}) {
  return Node(
    type: VideoEmbedBlockKeys.type,
    attributes: {
      VideoEmbedBlockKeys.url: url,
      VideoEmbedBlockKeys.fileName: fileName,
    },
  );
}

class VideoEmbedBlockComponentBuilder extends BlockComponentBuilder {
  VideoEmbedBlockComponentBuilder({super.configuration, this.onTap});

  /// タップ時（全画面表示）。ノート内の画像・動画をまとめて開くため、呼び出し側が処理する。
  final void Function(BuildContext context, String url)? onTap;

  @override
  BlockComponentWidget build(BlockComponentContext blockComponentContext) {
    final node = blockComponentContext.node;
    return VideoEmbedBlockComponentWidget(
      key: node.key,
      node: node,
      configuration: configuration,
      onTap: onTap,
      showActions: showActions(node),
      actionBuilder: (context, state) =>
          actionBuilder(blockComponentContext, state),
      actionTrailingBuilder: (context, state) =>
          actionTrailingBuilder(blockComponentContext, state),
    );
  }

  @override
  BlockComponentValidate get validate =>
      (node) => node.attributes[VideoEmbedBlockKeys.url] is String;
}

class VideoEmbedBlockComponentWidget extends BlockComponentStatefulWidget {
  const VideoEmbedBlockComponentWidget({
    super.key,
    required super.node,
    super.showActions,
    super.actionBuilder,
    super.actionTrailingBuilder,
    super.configuration = const BlockComponentConfiguration(),
    this.onTap,
  });

  final void Function(BuildContext context, String url)? onTap;

  @override
  State<VideoEmbedBlockComponentWidget> createState() =>
      _VideoEmbedBlockComponentWidgetState();
}

// SelectableMixinの実装は`divider_block_component.dart`の
// `_DividerBlockComponentWidgetState`に倣った（カーソルはブロック全体を
// 1つの位置として覆う、非テキストの「不可分ブロック」向けの標準的な実装）。
class _VideoEmbedBlockComponentWidgetState
    extends State<VideoEmbedBlockComponentWidget>
    with SelectableMixin, BlockComponentConfigurable {
  @override
  BlockComponentConfiguration get configuration => widget.configuration;

  @override
  Node get node => widget.node;

  final _contentKey = GlobalKey();
  RenderBox? get _renderBox => context.findRenderObject() as RenderBox?;

  @override
  Widget build(BuildContext context) {
    final url =
        widget.node.attributes[VideoEmbedBlockKeys.url] as String? ?? '';

    Widget child = Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360, maxHeight: 240),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          // メッセージ画面と同じ作り（chat_screen.dartの動画添付）。Webでは動画が別の
          // プラットフォームビューになりクリックを奪うため、動画の上に、領域全体を覆う
          // クリック専用の層を重ねてタップを受ける。
          child: SizedBox(
            width: 360,
            height: 202,
            child: Stack(
              children: [
                VideoThumbnail(url: url, canLoad: videoPlaybackSupported),
                Positioned.fill(
                  child: PointerInterceptor(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => widget.onTap?.call(context, url),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    child = Padding(key: _contentKey, padding: padding, child: child);

    final editorState = context.read<EditorState>();
    child = BlockSelectionContainer(
      node: node,
      delegate: this,
      listenable: editorState.selectionNotifier,
      remoteSelection: editorState.remoteSelections,
      blockColor: editorState.editorStyle.selectionColor,
      cursorColor: editorState.editorStyle.cursorColor,
      selectionColor: editorState.editorStyle.selectionColor,
      // 動画を押した時に行全体がアクセントカラーで囲まれないよう、選択の枠は描かない。
      supportTypes: const [],
      child: child,
    );

    if (widget.showActions && widget.actionBuilder != null) {
      child = BlockComponentActionWrapper(
        node: node,
        actionBuilder: widget.actionBuilder!,
        actionTrailingBuilder: widget.actionTrailingBuilder,
        child: child,
      );
    }

    return child;
  }

  @override
  Position start() => Position(path: widget.node.path, offset: 0);

  @override
  Position end() => Position(path: widget.node.path, offset: 1);

  @override
  Position getPositionInOffset(Offset start) => end();

  @override
  bool get shouldCursorBlink => false;

  @override
  CursorStyle get cursorStyle => CursorStyle.cover;

  @override
  Rect getBlockRect({bool shiftWithBaseOffset = false}) {
    return getRectsInSelection(Selection.invalid()).first;
  }

  @override
  Rect? getCursorRectInPosition(
    Position position, {
    bool shiftWithBaseOffset = false,
  }) {
    if (_renderBox == null) return null;
    return getRectsInSelection(
      Selection.collapsed(position),
      shiftWithBaseOffset: shiftWithBaseOffset,
    ).firstOrNull;
  }

  @override
  List<Rect> getRectsInSelection(
    Selection selection, {
    bool shiftWithBaseOffset = false,
  }) {
    if (_renderBox == null) return [];
    final parentBox = context.findRenderObject();
    final contentBox = _contentKey.currentContext?.findRenderObject();
    if (parentBox is RenderBox && contentBox is RenderBox) {
      return [
        (shiftWithBaseOffset
                ? contentBox.localToGlobal(Offset.zero, ancestor: parentBox)
                : Offset.zero) &
            contentBox.size,
      ];
    }
    return [Offset.zero & _renderBox!.size];
  }

  @override
  Selection getSelectionInRange(Offset start, Offset end) =>
      Selection.single(path: widget.node.path, startOffset: 0, endOffset: 1);

  @override
  Offset localToGlobal(Offset offset, {bool shiftWithBaseOffset = false}) =>
      _renderBox!.localToGlobal(offset);

  @override
  TextDirection textDirection() => TextDirection.ltr;
}
