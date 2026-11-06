import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../../widgets/blurred_viewer_route.dart';

/// 通話の映像を、画像・動画・PDFの拡大表示（`blurredViewerRoute`）と同じ見た目で
/// 拡大する（2026-11-03）。ぼかし＋暗幕の上に映像全体を出し、映像の外の余白のクリック・
/// タップ、Escで閉じる（戻る矢印は出さない）。
///
/// `MaterialApp.builder`の位置にある通話画面（`CallOverlay`、Web・コンピューター）には
/// `Navigator`が無い為、その場合は`Overlay`へ直接重ねる。`Navigator`がある画面
/// （スマホアプリの全画面通話）は、他のビューアと同じ`blurredViewerRoute`で開く（戻る操作が
/// 通話画面ではなく拡大だけを閉じるように）。
///
/// Webの`RTCVideoRenderer`は描画要素を1つしか持たず、拡大中は元の画面の同じ映像が
/// 空になる。閉じた時に[onClosed]を呼ぶので、呼び出し側は映像の部品を作り直すこと。
void showCallVideoViewer(
  BuildContext context, {
  required RTCVideoRenderer renderer,
  required bool mirror,
  VoidCallback? onClosed,
}) {
  void closed() => onClosed?.call();

  final navigator = Navigator.maybeOf(context);
  if (navigator != null) {
    navigator
        .push(
          blurredViewerRoute(
            (routeContext) => CallVideoViewer(
              renderer: renderer,
              mirror: mirror,
              onClose: () => Navigator.of(routeContext).pop(),
            ),
          ),
        )
        .then((_) => closed());
    return;
  }
  final overlay = Overlay.of(context);
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _FadeInBlurLayer(
      child: CallVideoViewer(
        renderer: renderer,
        mirror: mirror,
        onClose: () {
          entry.remove();
          closed();
        },
      ),
    ),
  );
  overlay.insert(entry);
}

/// `Overlay`へ直接重ねる時の、ぼかし＋暗幕とフェードイン（`blurredViewerRoute`と同じ値）。
class _FadeInBlurLayer extends StatelessWidget {
  const _FadeInBlurLayer({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 180),
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Stack(
          fit: StackFit.expand,
          children: [
            BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: ColoredBox(color: Colors.black.withValues(alpha: 0.45)),
            ),
            child!,
          ],
        ),
      ),
      child: Material(type: MaterialType.transparency, child: child),
    );
  }
}

class CallVideoViewer extends StatelessWidget {
  const CallVideoViewer({
    required this.renderer,
    required this.mirror,
    required this.onClose,
    super.key,
  });

  final RTCVideoRenderer renderer;
  final bool mirror;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          onClose();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      // 映像の外の余白のクリック・タップで閉じる。映像はホイール・ピンチで拡大・縮小、
      // ドラッグで移動出来る（画像の拡大表示と同じ`InteractiveViewer`、2026-11-03）。
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onClose,
        child: SizedBox.expand(
          child: InteractiveViewer(
            maxScale: 8,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: ValueListenableBuilder<RTCVideoValue>(
                  valueListenable: renderer,
                  builder: (context, value, _) => AspectRatio(
                    aspectRatio: value.aspectRatio > 0
                        ? value.aspectRatio
                        : 16 / 9,
                    child: PointerInterceptor(
                      // 映像自身のタップでは閉じない。
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {},
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: RTCVideoView(
                            key: ObjectKey(renderer),
                            renderer,
                            mirror: mirror,
                            objectFit: RTCVideoViewObjectFit
                                .RTCVideoViewObjectFitContain,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
