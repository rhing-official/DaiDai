import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../../models/album_item.dart';
import '../../widgets/swipe_gestures.dart';

/// アルバム内の画像・動画の全画面スワイプビューア（2026-08-30追加）。
///
/// `lib/features/chat/chat_screen.dart`の`_MediaViewerScreen`はメッセージ
/// （返信ジャンプ・矢印キー送り/戻し・シークバー付き動画コントロール等）に
/// 強く依存した作りのため、`AlbumItem`向けに流用せず軽量な専用実装にした
/// （基本のスワイプ・ピンチズーム・動画のタップ再生/一時停止のみ対応）。
/// 表示領域外（画像は非ズーム時の画面全体、動画はレターボックス部分）を
/// タップすると閉じる（2026-09-26追加、`lib/widgets/media_viewer_screen.dart`
/// の`_ImageViewerPage`/`_VideoViewerPage`と同じ方式に揃えた）。モバイルの
/// スワイプでの前後移動は元々`PinchPriorityPageView`内蔵の`PageView`が
/// 対応済みのため、コンピューターでも同様に移動できるよう矢印キーでの
/// 前後移動を追加した（2026-09-26追加、`lib/widgets/media_viewer_screen.dart`
/// の`_MediaViewerScreenState`と同じ`Focus`+`onKeyEvent`方式）。
class AlbumMediaViewerScreen extends StatefulWidget {
  const AlbumMediaViewerScreen({
    super.key,
    required this.items,
    required this.initialIndex,
  });

  final List<AlbumItem> items;
  final int initialIndex;

  @override
  State<AlbumMediaViewerScreen> createState() => _AlbumMediaViewerScreenState();
}

class _AlbumMediaViewerScreenState extends State<AlbumMediaViewerScreen> {
  late final int _safeInitialIndex = widget.initialIndex.clamp(
    0,
    widget.items.length - 1,
  );
  late final PageController _pageController = PageController(
    initialPage: _safeInitialIndex,
  );
  final FocusNode _focusNode = FocusNode();

  static const _pageChangeDuration = Duration(milliseconds: 200);

  @override
  void dispose() {
    _pageController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Focus(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            _pageController.previousPage(
              duration: _pageChangeDuration,
              curve: Curves.easeInOut,
            );
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
            _pageController.nextPage(
              duration: _pageChangeDuration,
              curve: Curves.easeInOut,
            );
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: PinchPriorityPageView(
          controller: _pageController,
          itemCount: widget.items.length,
          onDismiss: () => Navigator.of(context).pop(),
          itemBuilder: (context, index) {
            final item = widget.items[index];
            return item.contentType == 'video'
                ? _AlbumVideoPage(url: item.url)
                : _AlbumImagePage(url: item.url);
          },
        ),
      ),
    );
  }
}

/// `lib/widgets/media_viewer_screen.dart`の`_ImageViewerPage`と同じ
/// 「ズームしていない時だけ画面のどこをタップしても閉じる」方式（2026-09-26
/// 変更。以前は表示領域外相当のヒットテストを行っておらず、画像全体を覆う
/// 内側の`GestureDetector`が全てのタップを無条件に握りつぶしていたため、
/// タップでは一切閉じられなかった）。
class _AlbumImagePage extends StatefulWidget {
  const _AlbumImagePage({required this.url});

  final String url;

  @override
  State<_AlbumImagePage> createState() => _AlbumImagePageState();
}

class _AlbumImagePageState extends State<_AlbumImagePage> {
  final _transformationController = TransformationController();

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  void _handleTap() {
    final scale = _transformationController.value.getMaxScaleOnAxis();
    if (scale <= 1.01) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _handleTap,
      child: SizedBox.expand(
        child: InteractiveViewer(
          transformationController: _transformationController,
          child: Image.network(widget.url, fit: BoxFit.contain),
        ),
      ),
    );
  }
}

class _AlbumVideoPage extends StatefulWidget {
  const _AlbumVideoPage({required this.url});

  final String url;

  @override
  State<_AlbumVideoPage> createState() => _AlbumVideoPageState();
}

class _AlbumVideoPageState extends State<_AlbumVideoPage> {
  late final VideoPlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _controller.initialize().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _togglePlayback() {
    setState(() {
      _controller.value.isPlaying ? _controller.pause() : _controller.play();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_controller.value.isInitialized) {
      return const SizedBox.shrink();
    }
    // `media_viewer_screen.dart`の`_VideoViewerPage`と同じ「外側
    // （レターボックス部分）をタップすると閉じる、動画本体をタップすると
    // 再生/一時停止をトグルする」という二重構造（2026-09-26追加）。外側の
    // `GestureDetector`が`Expanded`全体（レターボックス含む）を覆って
    // `onTap`で閉じ、`AspectRatio`の内側（実際の動画の矩形）にトグル用の
    // `GestureDetector`を新たに設けて外側へのタップ伝播を止める。
    // 進捗バーは動画の矩形の外（＝閉じる判定の対象領域）に出すと意図せず
    // 閉じてしまうため、`Column`の兄弟要素として動画エリアの下に独立させた。
    return Column(
      children: [
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(context).pop(),
            child: Center(
              child: AspectRatio(
                aspectRatio: _controller.value.aspectRatio,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _togglePlayback,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      VideoPlayer(_controller),
                      if (!_controller.value.isPlaying)
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.black45,
                            shape: BoxShape.circle,
                          ),
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: Icon(
                              Icons.play_arrow,
                              color: Colors.white,
                              size: 48,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        VideoProgressIndicator(_controller, allowScrubbing: true),
      ],
    );
  }
}
