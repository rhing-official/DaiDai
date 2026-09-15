import 'dart:async';
import 'dart:io' show File;
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// [CameraCaptureScreen]が[Navigator.pop]で返す撮影結果。
class CapturedMedia {
  const CapturedMedia({
    required this.bytes,
    required this.fileName,
    required this.isVideo,
  });

  final Uint8List bytes;
  final String fileName;
  final bool isVideo;
}

enum _CaptureMode { photo, video }

/// 撮影直後のプレビュー動画（ローカルファイル）を再生するコントローラーを
/// 作る（2026-09-15追加）。Web版の`XFile.path`はblob URLを返すため
/// `networkUrl`で、それ以外のプラットフォームでは`File`経由で再生する
/// （`camera`パッケージの対応プラットフォームは`video_thumbnail.dart`の
/// `videoPlaybackSupported`が示す`video_player`の対応プラットフォームと
/// 一致するため、この画面に到達できる環境であれば再生も問題なく動く）。
VideoPlayerController _createLocalVideoController(String path) {
  if (kIsWeb) {
    return VideoPlayerController.networkUrl(Uri.parse(path));
  }
  return VideoPlayerController.file(File(path));
}

/// ＋ボタンの「撮影」から開くアプリ内カメラ画面（技術仕様書5.6参照、
/// 2026-08-10追加）。OS標準のカメラアプリは呼ばず、`camera`パッケージで
/// プレビューを自前描画する。画面内を横スワイプすると写真⇔録画モードを
/// 切り替えられ、シャッターボタンの色でモードを判別できる（写真＝白、
/// 録画＝赤）。起動時のデフォルトは写真モード。録画の開始/終了は共に
/// シャッターボタンのタップ（1回目で開始・2回目で終了、長押し録画ではない）。
/// 前面/背面カメラの切り替えボタン（右上）と、写真/動画モードを一目で
/// 判別できるアイコンインジケーター（シャッター上、タップでも切替可）を
/// 持つ（2026-08-10追加、実機カメラアプリに近いUIへの改善）。
///
/// 録画中はシャッター中央に停止アイコンを表示し、外周にパルスするリングと
/// 画面上部に経過時間つきのREC表示を出すことで、録画が進行中であることを
/// 常に視認できるようにしている。また撮影完了と同時に確認なく送信して
/// いた挙動をやめ、撮った写真/動画をこの画面内でプレビューし、「送信」を
/// 明示的に押すまでは呼び出し元（メッセージ送信パイプライン）へ渡さない
/// （「撮り直す」で破棄してライブカメラに戻れる、2026-09-15追加）。
class CameraCaptureScreen extends StatefulWidget {
  const CameraCaptureScreen({super.key});

  @override
  State<CameraCaptureScreen> createState() => _CameraCaptureScreenState();
}

class _CameraCaptureScreenState extends State<CameraCaptureScreen>
    with SingleTickerProviderStateMixin {
  CameraController? _controller;
  _CaptureMode _mode = _CaptureMode.photo;
  bool _isRecording = false;
  bool _busy = false;
  String? _errorMessage;

  List<CameraDescription> _cameras = [];
  int _selectedCameraIndex = 0;

  Timer? _recordingTimer;
  int _recordingSeconds = 0;
  late final AnimationController _pulseController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  /// 撮影済みだが未送信のメディア（nullなら通常のライブカメラ表示）。
  CapturedMedia? _preview;
  VideoPlayerController? _previewVideoController;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _errorMessage = 'カメラが見つかりませんでした');
        return;
      }
      _cameras = cameras;
      // 背面カメラを既定にする（実機のカメラアプリと同じ挙動）。
      // 見つからない機種（PC内蔵カメラ等）では先頭のカメラにフォールバック。
      final backIndex = cameras.indexWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
      );
      _selectedCameraIndex = backIndex >= 0 ? backIndex : 0;
      await _startController(cameras[_selectedCameraIndex]);
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = 'カメラを起動できませんでした: $e');
      }
    }
  }

  Future<void> _startController(CameraDescription camera) async {
    final controller = CameraController(
      camera,
      ResolutionPreset.high,
      enableAudio: true,
    );
    await controller.initialize();
    if (!mounted) {
      await controller.dispose();
      return;
    }
    setState(() => _controller = controller);
  }

  /// 前面/背面カメラの切り替え（2026-08-10追加）。録画中は不可
  /// （モード切替のスワイプ・タップと同じ制約）。カメラが1台しか
  /// 無い機種ではボタン自体を表示しない（build参照）。
  Future<void> _switchCamera() async {
    if (_cameras.length < 2 || _isRecording || _busy) return;
    final oldController = _controller;
    setState(() => _controller = null);
    await oldController?.dispose();
    _selectedCameraIndex = (_selectedCameraIndex + 1) % _cameras.length;
    try {
      await _startController(_cameras[_selectedCameraIndex]);
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = 'カメラを切り替えられませんでした: $e');
      }
    }
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    _pulseController.dispose();
    _previewVideoController?.dispose();
    _controller?.dispose();
    super.dispose();
  }

  void _handleSwipe(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (velocity < 0) {
      _setMode(_CaptureMode.video);
    } else if (velocity > 0) {
      _setMode(_CaptureMode.photo);
    }
  }

  /// 横スワイプに加えて、シャッター上のモードアイコン（[_ModeIconButton]）を
  /// 直接タップしても切り替えられるようにする（2026-08-10追加）。
  void _setMode(_CaptureMode mode) {
    if (_isRecording || _mode == mode) return; // 録画中はモード切替不可。
    setState(() => _mode = mode);
  }

  /// 録画開始時の視覚フィードバック（パルスリング・経過時間タイマー）を
  /// 始める（2026-09-15追加）。
  void _startRecordingFeedback() {
    _pulseController.repeat(reverse: true);
    _recordingTimer?.cancel();
    _recordingSeconds = 0;
    _recordingTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => setState(() => _recordingSeconds++),
    );
  }

  void _stopRecordingFeedback() {
    _pulseController
      ..stop()
      ..reset();
    _recordingTimer?.cancel();
    _recordingTimer = null;
  }

  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Future<void> _onShutterTap() async {
    final controller = _controller;
    if (controller == null || _busy) return;

    if (_mode == _CaptureMode.photo) {
      setState(() => _busy = true);
      try {
        final file = await controller.takePicture();
        final bytes = await file.readAsBytes();
        if (!mounted) return;
        setState(() {
          _preview = CapturedMedia(
            bytes: bytes,
            fileName: file.name,
            isVideo: false,
          );
        });
      } finally {
        if (mounted) setState(() => _busy = false);
      }
      return;
    }

    // 録画モード: 1回目のタップで開始、2回目のタップで終了する
    // （長押し録画ではない、技術仕様書5.6参照）。
    if (!_isRecording) {
      await controller.startVideoRecording();
      _startRecordingFeedback();
      setState(() => _isRecording = true);
    } else {
      setState(() => _busy = true);
      try {
        final file = await controller.stopVideoRecording();
        _stopRecordingFeedback();
        if (mounted) setState(() => _isRecording = false);
        final bytes = await file.readAsBytes();
        if (!mounted) return;

        VideoPlayerController? previewController;
        try {
          previewController = _createLocalVideoController(file.path);
          await previewController.initialize();
          previewController.setLooping(true);
          unawaited(previewController.play());
        } catch (_) {
          // 撮影直後のプレビュー再生に失敗しても、撮影結果自体
          // （送信/撮り直しの選択）は引き続き提示する。
          await previewController?.dispose();
          previewController = null;
        }
        if (!mounted) {
          await previewController?.dispose();
          return;
        }
        setState(() {
          _preview = CapturedMedia(
            bytes: bytes,
            fileName: file.name,
            isVideo: true,
          );
          _previewVideoController = previewController;
        });
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    }
  }

  /// プレビュー中の「撮り直す」: 撮影結果を破棄してライブカメラに戻る
  /// （2026-09-15追加）。
  Future<void> _retake() async {
    final previewController = _previewVideoController;
    setState(() {
      _preview = null;
      _previewVideoController = null;
    });
    await previewController?.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final preview = _preview;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        child: _errorMessage != null
            ? Center(
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(color: Colors.white),
                ),
              )
            : preview != null
            ? _buildPreview(preview)
            : controller == null || !controller.value.isInitialized
            ? const Center(child: CircularProgressIndicator())
            : GestureDetector(
                onHorizontalDragEnd: _handleSwipe,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Center(child: CameraPreview(controller)),
                    // 前面/背面カメラ切り替え（2026-08-10追加）。カメラが
                    // 1台のみの機種ではボタン自体を出さない。
                    if (_cameras.length > 1)
                      Positioned(
                        top: 16,
                        right: 16,
                        child: IconButton(
                          onPressed: _isRecording ? null : _switchCamera,
                          icon: const Icon(Icons.cameraswitch_outlined),
                          color: Colors.white,
                          disabledColor: Colors.white38,
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.black38,
                          ),
                        ),
                      ),
                    // 録画中インジケーター「● 00:12」（2026-09-15追加）。
                    // 録画が進行中であることを常に視認できるようにする。
                    if (_isRecording)
                      Positioned(
                        top: 16,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                AnimatedBuilder(
                                  animation: _pulseController,
                                  builder: (context, child) => Opacity(
                                    opacity: 0.4 + _pulseController.value * 0.6,
                                    child: child,
                                  ),
                                  child: const Icon(
                                    Icons.circle,
                                    color: Colors.red,
                                    size: 12,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _formatDuration(_recordingSeconds),
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    // 写真/動画モードを一目で判別できるアイコン
                    // インジケーター（2026-08-10追加）。シャッターの色分けに
                    // 加え、タップでも直接モードを切り替えられる。
                    Positioned(
                      bottom: 110,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _ModeIconButton(
                              icon: Icons.photo_camera,
                              selected: _mode == _CaptureMode.photo,
                              activeColor: Colors.white,
                              onTap: () => _setMode(_CaptureMode.photo),
                            ),
                            const SizedBox(width: 28),
                            _ModeIconButton(
                              icon: Icons.videocam,
                              selected: _mode == _CaptureMode.video,
                              activeColor: Colors.red,
                              onTap: () => _setMode(_CaptureMode.video),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 24,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: GestureDetector(
                          onTap: _onShutterTap,
                          child: SizedBox(
                            width: 96,
                            height: 96,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                // 録画中は外周にパルスするリングを重ねて、
                                // シャッターの色が録画中/待機中で見分けが
                                // つかない問題を補う（2026-09-15追加）。
                                if (_isRecording)
                                  AnimatedBuilder(
                                    animation: _pulseController,
                                    builder: (context, child) => Container(
                                      width: 96,
                                      height: 96,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: Colors.red.withValues(
                                            alpha:
                                                0.3 +
                                                _pulseController.value * 0.4,
                                          ),
                                          width: 3,
                                        ),
                                      ),
                                    ),
                                  ),
                                Container(
                                  width: 72,
                                  height: 72,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 4,
                                    ),
                                    color: _mode == _CaptureMode.photo
                                        ? Colors.white
                                        : Colors.red,
                                  ),
                                  // 録画中は中央に停止アイコン（角丸四角）を
                                  // 表示し、「押せば止まる」ことを示す
                                  // （2026-09-15追加）。
                                  child: _isRecording
                                      ? Center(
                                          child: Container(
                                            width: 24,
                                            height: 24,
                                            decoration: BoxDecoration(
                                              color: Colors.white,
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                          ),
                                        )
                                      : null,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  /// 撮影結果のプレビュー画面（2026-09-15追加）。「送信」を明示的に押すまで
  /// 呼び出し元へは返さず、「撮り直す」でライブカメラに戻れる。
  Widget _buildPreview(CapturedMedia preview) {
    final videoController = _previewVideoController;
    return Stack(
      fit: StackFit.expand,
      children: [
        Center(
          child: preview.isVideo
              ? (videoController != null && videoController.value.isInitialized
                    ? AspectRatio(
                        aspectRatio: videoController.value.aspectRatio,
                        child: VideoPlayer(videoController),
                      )
                    : const CircularProgressIndicator())
              : Image.memory(preview.bytes, fit: BoxFit.contain),
        ),
        Positioned(
          bottom: 32,
          left: 24,
          right: 24,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              OutlinedButton(
                onPressed: _retake,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                ),
                child: const Text('撮り直す'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(preview),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                ),
                child: const Text('送信'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// シャッター上の写真/動画モードインジケーター1つ分（2026-08-10追加）。
/// 選択中はシャッターと同じ色（写真＝白、動画＝赤）で塗り、一目でどちらの
/// モードか判別できるようにする。タップでも直接そのモードに切り替えられる。
class _ModeIconButton extends StatelessWidget {
  const _ModeIconButton({
    required this.icon,
    required this.selected,
    required this.activeColor,
    required this.onTap,
  });

  final IconData icon;
  final bool selected;
  final Color activeColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected ? activeColor : Colors.white.withValues(alpha: 0.15),
        ),
        child: Icon(
          icon,
          size: 22,
          color: selected && activeColor == Colors.white
              ? Colors.black
              : Colors.white,
        ),
      ),
    );
  }
}
