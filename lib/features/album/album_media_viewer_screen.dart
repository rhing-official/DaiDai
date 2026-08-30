import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../models/album_item.dart';

/// アルバム内の画像・動画の全画面スワイプビューア（2026-08-30追加）。
///
/// `lib/features/chat/chat_screen.dart`の`_MediaViewerScreen`はメッセージ
/// （返信ジャンプ・矢印キー送り/戻し・シークバー付き動画コントロール等）に
/// 強く依存した作りのため、`AlbumItem`向けに流用せず軽量な専用実装にした
/// （基本のスワイプ・ピンチズーム・動画のタップ再生/一時停止のみ対応）。
class AlbumMediaViewerScreen extends StatelessWidget {
  const AlbumMediaViewerScreen({
    super.key,
    required this.items,
    required this.initialIndex,
  });

  final List<AlbumItem> items;
  final int initialIndex;

  @override
  Widget build(BuildContext context) {
    final safeInitialIndex = initialIndex.clamp(0, items.length - 1);
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
      body: PageView.builder(
        controller: PageController(initialPage: safeInitialIndex),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          return item.contentType == 'video'
              ? _AlbumVideoPage(url: item.url)
              : _AlbumImagePage(url: item.url);
        },
      ),
    );
  }
}

class _AlbumImagePage extends StatelessWidget {
  const _AlbumImagePage({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).pop(),
      child: GestureDetector(
        onTap: () {},
        child: SizedBox.expand(
          child: InteractiveViewer(
            child: Image.network(url, fit: BoxFit.contain),
          ),
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
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    return GestureDetector(
      onTap: _togglePlayback,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Center(
            child: AspectRatio(
              aspectRatio: _controller.value.aspectRatio,
              child: VideoPlayer(_controller),
            ),
          ),
          if (!_controller.value.isPlaying)
            const DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black45,
                shape: BoxShape.circle,
              ),
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Icon(Icons.play_arrow, color: Colors.white, size: 48),
              ),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: VideoProgressIndicator(_controller, allowScrubbing: true),
          ),
        ],
      ),
    );
  }
}
