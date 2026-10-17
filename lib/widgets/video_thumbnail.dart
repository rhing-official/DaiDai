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

/// サムネイルとして表示する動画内の位置（2026-10-16追加）。基本は1秒、
/// 1.5秒に満たない短い動画は先頭付近（0.3秒か、それより短ければ半分）。
/// 長さが不明（0）なら先頭。サーバー側のサムネイル生成（`functions/src/index.ts`
/// の`generateVideoThumbnail`）と見え方をそろえるための共通ルール。
Duration previewPositionFor(Duration duration) {
  const preferred = Duration(seconds: 1);
  const shortLimit = Duration(milliseconds: 1500);
  if (duration >= shortLimit) return preferred;
  if (duration <= Duration.zero) return Duration.zero;
  const near = Duration(milliseconds: 300);
  final half = duration ~/ 2;
  return half < near ? half : near;
}

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
    this.showPlayIcon = true,
    this.thumbnailUrl,
  });

  final String url;

  /// サーバー側（Cloud Functions）が動画の1秒位置から生成したサムネイル画像
  /// （`MessageFileMetadata.thumbnailUrl`、2026-10-16追加）。あれば動画自体は
  /// 読み込まず、この画像を表示する。Webの一部ブラウザ（Firefox系）では
  /// `VideoPlayerController.initialize`が完了せず先頭フレームを取れないため、
  /// 画像を優先する。未生成（null）の間だけ動画から先頭付近のコマを取る。
  final String? thumbnailUrl;
  final bool canLoad;

  /// 指定時は`size`×`size`の正方形（`BoxFit.cover`でクロップ）で表示する
  /// （返信引用プレビュー・アルバムグリッド用）。未指定なら既存の280px
  /// 固定＋アスペクト比維持のレターボックス表示（メッセージ本文の添付
  /// 表示用）。
  final double? size;

  /// 正方形モード（[size]指定時）で再生アイコンを描くか。拡大縮小される
  /// 親（`FittedBox`等）の中に置く時はfalseにし、アイコンだけ別に重ねる
  /// （アイコンが一緒に拡大されて単一動画より大きく見えるのを防ぐ、
  /// 2026-10-16、複数添付グリッド用）。
  final bool showPlayIcon;

  @override
  State<VideoThumbnail> createState() => _VideoThumbnailState();
}

class _VideoThumbnailState extends State<VideoThumbnail> {
  VideoPlayerController? _controller;
  bool _ready = false;

  @override
  void didUpdateWidget(covariant VideoThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    // サムネイル画像が後から生成された場合、動画の読み込みは不要になる。
    if (oldWidget.thumbnailUrl == null && widget.thumbnailUrl != null) {
      _controller?.dispose();
      _controller = null;
      _ready = false;
    }
  }

  @override
  void initState() {
    super.initState();
    if (!widget.canLoad || widget.thumbnailUrl != null) return;
    final controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _controller = controller;
    controller
        .initialize()
        .then((_) async {
          // 先頭（0秒）は暗転・フェードインで黒くなりやすいため、サーバー側の
          // サムネイル生成（Cloud Functions、1秒位置）と同じ位置のコマを出す
          // （2026-10-16）。短い動画は長さに収まる位置にする。
          await controller.seekTo(
            previewPositionFor(controller.value.duration),
          );
          if (mounted) setState(() => _ready = true);
        })
        .catchError((_) {});
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  static const _playIcon = VideoPlayBadge();

  Widget _serverThumbnail(String thumbUrl) {
    final squareSize = widget.size;
    Widget image(double? width) => Image.network(
      thumbUrl,
      width: width,
      height: squareSize,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => Container(color: Colors.black87),
    );
    if (squareSize != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(
          width: squareSize,
          height: squareSize,
          child: Stack(
            fit: StackFit.expand,
            children: [
              image(squareSize),
              if (widget.showPlayIcon)
                Icon(
                  Icons.play_arrow,
                  color: Colors.white,
                  size: squareSize / 2,
                ),
            ],
          ),
        ),
      );
    }
    return SizedBox(
      width: 280,
      child: Stack(
        children: [
          image(280),
          const Positioned.fill(child: _playIcon),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final thumbUrl = widget.thumbnailUrl;
    if (thumbUrl != null) return _serverThumbnail(thumbUrl);
    final controller = _controller;
    final squareSize = widget.size;
    // ダイアログ・メニュー等が上に被さっている間（自分の乗っているルートが
    // 最前面でない間）は、実体（`VideoPlayer`＝Web版ではプラットフォーム
    // ビュー＝実DOMの<video>要素）を一切マウントしない。`BackdropFilter`を
    // 使うガラスUIのダイアログとプラットフォームビューの組み合わせは
    // Flutter Web既知の弱点で、Flutterの描画順としては背面にあるはずの
    // 動画がブラウザ実際のヒットテストでは遮蔽されずクリックが素通り
    // してしまうことがある（投票ダイアログの回答中に背景の動画が再生されて
    // しまう不具合、2026-09-06発覚）。`ModalRoute.of`はcontextの依存登録に
    // より、ダイアログの開閉のたびに自動で再ビルドされる。
    final isTopRoute = ModalRoute.of(context)?.isCurrent ?? true;
    if (squareSize != null) {
      // 正方形モード。アスペクト比を維持したレターボックスではなく、
      // ボックスいっぱいにクロップして小さいサムネイルとして見やすくする。
      final content = _ready && controller != null && isTopRoute
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
              if (widget.showPlayIcon)
                Icon(
                  Icons.play_arrow,
                  color: Colors.white,
                  size: squareSize / 2,
                ),
            ],
          ),
        ),
      );
    }
    if (_ready && controller != null && isTopRoute) {
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

/// 動画の再生アイコン（半透明の黒い丸＋白い再生マーク）。単一の動画メッセージと
/// 複数添付グリッドで同じ大きさ・見た目にそろえるため共通化した（2026-10-16）。
class VideoPlayBadge extends StatelessWidget {
  const VideoPlayBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black45,
          shape: BoxShape.circle,
        ),
        child: Padding(
          padding: EdgeInsets.all(8),
          child: Icon(Icons.play_arrow, color: Colors.white, size: 28),
        ),
      ),
    );
  }
}
