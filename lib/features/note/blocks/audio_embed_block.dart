import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:provider/provider.dart' as provider;

import '../../../providers/audio_playback_provider.dart';

/// 音声ファイルの再生プレビューブロック（2026-11-15追加）。再生はチャットの音声と同じ
/// `audioPlaybackProvider`（アプリ全体で1つ）を使う。
class AudioEmbedBlockKeys {
  const AudioEmbedBlockKeys._();

  static const String type = 'audio_embed';
  static const String url = 'url';
  static const String fileName = 'file_name';
}

Node audioEmbedNode({required String url, required String fileName}) {
  return Node(
    type: AudioEmbedBlockKeys.type,
    attributes: {
      AudioEmbedBlockKeys.url: url,
      AudioEmbedBlockKeys.fileName: fileName,
    },
  );
}

class AudioEmbedBlockComponentBuilder extends BlockComponentBuilder {
  AudioEmbedBlockComponentBuilder({super.configuration});

  @override
  BlockComponentWidget build(BlockComponentContext blockComponentContext) {
    final node = blockComponentContext.node;
    return AudioEmbedBlockComponentWidget(
      key: node.key,
      node: node,
      configuration: configuration,
      showActions: showActions(node),
      actionBuilder: (context, state) =>
          actionBuilder(blockComponentContext, state),
      actionTrailingBuilder: (context, state) =>
          actionTrailingBuilder(blockComponentContext, state),
    );
  }

  @override
  BlockComponentValidate get validate =>
      (node) => node.attributes[AudioEmbedBlockKeys.url] is String;
}

class AudioEmbedBlockComponentWidget extends BlockComponentStatefulWidget {
  const AudioEmbedBlockComponentWidget({
    super.key,
    required super.node,
    super.showActions,
    super.actionBuilder,
    super.actionTrailingBuilder,
    super.configuration = const BlockComponentConfiguration(),
  });

  @override
  State<AudioEmbedBlockComponentWidget> createState() =>
      _AudioEmbedBlockComponentWidgetState();
}

// SelectableMixinの実装は`divider_block_component.dart`の
// `_DividerBlockComponentWidgetState`に倣った（カーソルはブロック全体を
// 1つの位置として覆う、非テキストの「不可分ブロック」向けの標準的な実装）。
class _AudioEmbedBlockComponentWidgetState
    extends State<AudioEmbedBlockComponentWidget>
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
        widget.node.attributes[AudioEmbedBlockKeys.url] as String? ?? '';

    final fileName =
        widget.node.attributes[AudioEmbedBlockKeys.fileName] as String? ?? '';

    Widget child = _AudioPlayerRow(
      id: 'note:${widget.node.id}:$url',
      url: url,
      fileName: fileName,
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
      supportTypes: const [
        BlockSelectionType.block,
        BlockSelectionType.cursor,
        BlockSelectionType.selection,
      ],
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

class _AudioPlayerRow extends ConsumerWidget {
  const _AudioPlayerRow({
    required this.id,
    required this.url,
    required this.fileName,
  });

  final String id;
  final String url;
  final String fileName;

  static String _fmt(Duration d) =>
      '${d.inMinutes}:${d.inSeconds.remainder(60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(audioPlaybackProvider);
    final mine = current.messageId == id;
    final playing = mine && current.playing;
    final duration = mine ? current.duration : null;
    final position = mine ? current.position : Duration.zero;
    final total = duration?.inMilliseconds ?? 0;
    final scheme = Theme.of(context).colorScheme;
    final notifier = ref.read(audioPlaybackProvider.notifier);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: scheme.outlineVariant),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            IconButton(
              icon: Icon(playing ? Icons.pause : Icons.play_arrow),
              onPressed: () =>
                  notifier.toggle(messageId: id, url: url, title: fileName),
            ),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  if (total > 0)
                    SizedBox(
                      height: 24,
                      child: Slider(
                        value: position.inMilliseconds
                            .clamp(0, total)
                            .toDouble(),
                        max: total.toDouble(),
                        onChanged: (v) =>
                            notifier.seek(Duration(milliseconds: v.round())),
                      ),
                    ),
                ],
              ),
            ),
            if (total > 0)
              Text(
                '${_fmt(position)} / ${_fmt(duration!)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
      ),
    );
  }
}
