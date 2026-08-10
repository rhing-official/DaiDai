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
      final controller = CameraController(
        cameras.first,
        ResolutionPreset.high,
        enableAudio: true,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = 'カメラを起動できませんでした: $e');
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
    if (_isRecording) return; // 録画中はモード切替不可。
    if (velocity < 0 && _mode == _CaptureMode.photo) {
      setState(() => _mode = _CaptureMode.video);
    } else if (velocity > 0 && _mode == _CaptureMode.video) {
      setState(() => _mode = _CaptureMode.photo);
    }
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
