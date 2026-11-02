import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_ui_style.dart';
import '../providers/app_ui_style_provider.dart';
import 'glass/glass_surface.dart';
import 'media_preview_frame.dart';

/// メッセージ画面などのペインの中に重ねて出す、少し小さめの中央ポップアップ
/// （2026-11-02、アルバムを開く時に使う）。ペインの表示領域を超えない（広い画面の
/// サイドバーを覆わない）よう、`Navigator`のダイアログではなくペイン内の`Stack`に
/// 重ねる。背景の暗幕をタップすると[onClose]。大きさはペインの約7割（最大560×640）。
/// 面はUIスタイルに合わせる（影は使わない）。
class PaneModalPopup extends ConsumerWidget {
  const PaneModalPopup({required this.child, required this.onClose, super.key});

  final Widget child;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uiStyle = ref.watch(appUiStyleProvider);
    final radius = BorderRadius.circular(16);
    final surface = switch (uiStyle) {
      AppUiStyle.gekiga => GekigaStraightMonochromeBox(
        isMe: true,
        child: child,
      ),
      AppUiStyle.glass => GlassSurface(
        variant: GlassVariant.floating,
        borderRadius: radius,
        child: ClipRRect(borderRadius: radius, child: child),
      ),
      _ => Material(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: child,
      ),
    };
    return Stack(
      fit: StackFit.expand,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onClose,
          child: const ColoredBox(color: Colors.black45),
        ),
        Center(
          child: FractionallySizedBox(
            widthFactor: 0.7,
            heightFactor: 0.7,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560, maxHeight: 640),
              child: surface,
            ),
          ),
        ),
      ],
    );
  }
}
