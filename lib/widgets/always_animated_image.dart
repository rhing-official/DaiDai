import 'package:flutter/material.dart';

/// 子孫の`Image`が端末のアニメーション設定（`MediaQuery.disableAnimations`、
/// OSの「アニメーション効果」オフ・視覚効果の軽減）で一時停止されず、GIF等の
/// 複数フレーム画像が常に再生されるようにする薄いラッパー（2026-10-04追加）。
///
/// `Image`ウィジェットは`disableAnimations`が真の間、GIFを1コマ目で止める
/// 仕様のため、アイコン表示（`GlassAvatar`等）だけをこれで包んでいる。
/// 画面遷移など他のアニメーションには影響しない（`MediaQuery`の上書きは
/// 子孫に限られる）。
class AlwaysAnimatedImage extends StatelessWidget {
  const AlwaysAnimatedImage({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: false),
      child: child,
    );
  }
}
