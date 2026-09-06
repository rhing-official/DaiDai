import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import 'video_thumbnail.dart' show videoPlaybackSupported;

/// 画像・動画1件の全画面プレビュー（2026-09-06追加、投票の選択肢サムネイル
/// タップ用に新規作成）。チャットの`_MediaViewerScreen`（複数メッセージ間の
/// ページング・シークバー・早送りボタン付き）は本格的すぎるため流用せず、
/// 単一メディアの表示に絞った軽量な共有ウィジェットとして独立させた。
/// [mediaType]は'image'|'video'。動画再生非対応環境（Linux/Windows、
/// [videoPlaybackSupported]参照）では viewer を開かず外部アプリで再生する。
Future<void> showMediaFullscreenViewer(
  BuildContext context, {
  required String url,
  required String mediaType,
}) {
  if (mediaType == 'video' && !videoPlaybackSupported) {
    return launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }
  return Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) =>
          _MediaFullscreenViewerScreen(url: url, mediaType: mediaType),
    ),
  );
}

class _MediaFullscreenViewerScreen extends StatelessWidget {
  const _MediaFullscreenViewerScreen({
    required this.url,
    required this.mediaType,
  });

  final String url;
  final String mediaType;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: mediaType == 'video'
            ? _VideoPreview(url: url)
            : InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                child: Image.network(url),
              ),
      ),
    );
  }
}

class _VideoPreview extends StatefulWidget {
  const _VideoPreview({required this.url});

  final String url;

  @override
  State<_VideoPreview> createState() => _VideoPreviewState();
}

class _VideoPreviewState extends State<_VideoPreview> {
  late final VideoPlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _controller.initialize().then((_) {
      if (!mounted) return;
      setState(() {});
      _controller.play();
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
      return const CircularProgressIndicator();
    }
    return GestureDetector(
      onTap: _togglePlayback,
      child: AspectRatio(
        aspectRatio: _controller.value.aspectRatio,
        child: Stack(
          fit: StackFit.expand,
          alignment: Alignment.center,
          children: [
            VideoPlayer(_controller),
            if (!_controller.value.isPlaying)
              Center(
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    color: Colors.black45,
                    shape: BoxShape.circle,
                  ),
                  child: const Padding(
                    padding: EdgeInsets.all(16),
                    child: Icon(
                      Icons.play_arrow,
                      color: Colors.white,
                      size: 40,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
