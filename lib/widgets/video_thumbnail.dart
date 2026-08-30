import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// `video_player`はiOS/Android/Web/macOSのみ対応（Linux/Windowsは非対応、
/// 技術仕様書5.8参照）。動画を扱う画面はこの判定でインアプリ再生可否を
/// 分岐する（`lib/features/chat/chat_screen.dart`の添付表示・
/// `lib/features/album/`のアルバム画面と共通、2026-08-30に
/// `chat_screen.dart`から切り出し）。
bool get videoPlaybackSupported =>
    kIsWeb || !(Platform.isWindows || Platform.isLinux);

/// 動画のインラインサムネイル。実際の最初のコマを表示する（当初は暗い
/// プレースホルダーのみだったが、ユーザー要望により変更）。実現には別途
/// サムネイル生成パッケージ（`video_thumbnail`等、Android/iOSのみ対応）を
/// 使わず、既に導入済みの`video_player`で`VideoPlayerController`を初期化
/// した直後（`play()`を呼ばない、＝先頭フレームで一時停止した状態）の
/// `VideoPlayer`ウィジェットをそのまま表示する。[canLoad]がfalse
/// （[videoPlaybackSupported]がfalse）の場合は読み込み自体を行わず、暗い
/// プレースホルダーのままにする。
///
/// 元は`lib/features/chat/chat_screen.dart`の`_VideoThumbnail`（メッセージ
/// 添付・返信引用プレビュー用）だったが、寄合アルバム機能（2026-08-30）の
/// グリッド表示でも同じロジックが必要になったため、公開ウィジェットとして
/// `lib/widgets/`へ切り出した。
class VideoThumbnail extends StatefulWidget {
  const VideoThumbnail({
    super.key,
    required this.url,
    required this.canLoad,
    this.size,
  });

  final String url;
  final bool canLoad;

  /// 指定時は`size`×`size`の正方形（`BoxFit.cover`でクロップ）で表示する
  /// （返信引用プレビュー・アルバムグリッド用）。未指定なら既存の280px
  /// 固定＋アスペクト比維持のレターボックス表示（メッセージ本文の添付
  /// 表示用）。
  final double? size;

  @override
  State<VideoThumbnail> createState() => _VideoThumbnailState();
}

class _VideoThumbnailState extends State<VideoThumbnail> {
  VideoPlayerController? _controller;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    if (!widget.canLoad) return;
    final controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _controller = controller;
    controller
        .initialize()
        .then((_) {
          if (mounted) setState(() => _ready = true);
        })
        .catchError((_) {});
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  static const _playIcon = Center(
    child: DecoratedBox(
      decoration: BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
      child: Padding(
        padding: EdgeInsets.all(8),
        child: Icon(Icons.play_arrow, color: Colors.white, size: 28),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final squareSize = widget.size;
    if (squareSize != null) {
      // 正方形モード。アスペクト比を維持したレターボックスではなく、
      // ボックスいっぱいにクロップして小さいサムネイルとして見やすくする。
      final content = _ready && controller != null
          ? FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: controller.value.size.width,
                height: controller.value.size.height,
                child: VideoPlayer(controller),
              ),
            )
          : Container(color: Colors.black87);
      return ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(
          width: squareSize,
          height: squareSize,
          child: Stack(
            fit: StackFit.expand,
            children: [
              content,
              Icon(Icons.play_arrow, color: Colors.white, size: squareSize / 2),
            ],
          ),
        ),
      );
    }
    if (_ready && controller != null) {
      return SizedBox(
        width: 280,
        child: AspectRatio(
          aspectRatio: controller.value.aspectRatio,
          child: Stack(
            fit: StackFit.expand,
            children: [VideoPlayer(controller), _playIcon],
          ),
        ),
      );
    }
    return SizedBox(
      width: 280,
      height: 280 * 9 / 16,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(color: Colors.black87),
          _playIcon,
        ],
      ),
    );
  }
}
