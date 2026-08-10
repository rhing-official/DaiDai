import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

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

/// ＋ボタンの「撮影」から開くアプリ内カメラ画面（技術仕様書5.6参照、
/// 2026-08-10追加）。OS標準のカメラアプリは呼ばず、`camera`パッケージで
/// プレビューを自前描画する。画面内を横スワイプすると写真⇔録画モードを
/// 切り替えられ、シャッターボタンの色でモードを判別できる（写真＝白、
/// 録画＝赤）。起動時のデフォルトは写真モード。録画の開始/終了は共に
/// シャッターボタンのタップ（1回目で開始・2回目で終了、長押し録画ではない）。
/// 前面/背面カメラの切り替えボタン（右上）と、写真/動画モードを一目で
/// 判別できるアイコンインジケーター（シャッター上、タップでも切替可）を
/// 持つ（2026-08-10追加、実機カメラアプリに近いUIへの改善）。
class CameraCaptureScreen extends StatefulWidget {
  const CameraCaptureScreen({super.key});

  @override
  State<CameraCaptureScreen> createState() => _CameraCaptureScreenState();
}

class _CameraCaptureScreenState extends State<CameraCaptureScreen> {
  CameraController? _controller;
  _CaptureMode _mode = _CaptureMode.photo;
  bool _isRecording = false;
  bool _busy = false;
  String? _errorMessage;

  List<CameraDescription> _cameras = [];
  int _selectedCameraIndex = 0;

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

  Future<void> _onShutterTap() async {
    final controller = _controller;
    if (controller == null || _busy) return;

    if (_mode == _CaptureMode.photo) {
      setState(() => _busy = true);
      try {
        final file = await controller.takePicture();
        final bytes = await file.readAsBytes();
        if (!mounted) return;
        Navigator.of(
          context,
        ).pop(CapturedMedia(bytes: bytes, fileName: file.name, isVideo: false));
      } finally {
        if (mounted) setState(() => _busy = false);
      }
      return;
    }

    // 録画モード: 1回目のタップで開始、2回目のタップで終了する
    // （長押し録画ではない、技術仕様書5.6参照）。
    if (!_isRecording) {
      await controller.startVideoRecording();
      setState(() => _isRecording = true);
    } else {
      setState(() => _busy = true);
      try {
        final file = await controller.stopVideoRecording();
        setState(() => _isRecording = false);
        final bytes = await file.readAsBytes();
        if (!mounted) return;
        Navigator.of(
          context,
        ).pop(CapturedMedia(bytes: bytes, fileName: file.name, isVideo: true));
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
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
                          child: Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 4),
                              color: _mode == _CaptureMode.photo
                                  ? Colors.white
                                  : Colors.red,
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
