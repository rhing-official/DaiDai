import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

/// 画像・映像・PDFの拡大表示用のルート（2026-10-30追加）。背景が透ける透明な
/// ルートで、下のメッセージ画面をぼかし＋薄い暗幕で重ね、「メッセージ画面の
/// 延長」として見せる。ビューア側の`Scaffold`は背景を透明にすること。影は使わず、
/// ぼかしと暗幕だけで境界を作る。
Route<T> blurredViewerRoute<T>(WidgetBuilder builder) {
  return PageRouteBuilder<T>(
    opaque: false,
    barrierDismissible: false,
    transitionDuration: const Duration(milliseconds: 180),
    reverseTransitionDuration: const Duration(milliseconds: 150),
    pageBuilder: (context, _, _) => builder(context),
    transitionsBuilder: (context, animation, _, child) => FadeTransition(
      opacity: animation,
      child: Stack(
        fit: StackFit.expand,
        children: [
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: ColoredBox(color: Colors.black.withValues(alpha: 0.45)),
          ),
          child,
        ],
      ),
    ),
  );
}
