import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_ui_style.dart';
import '../providers/app_ui_style_provider.dart';
import '../theme/block/block_theme.dart';
import 'app_dialog.dart';
import 'glass/glass_surface.dart';
import 'media_preview_frame.dart';

/// 少し小さめの中央ポップアップをダイアログで出す（2026-11-05、アルバムの詳細に使う）。
/// カレンダーの月表示などと同じ[showAppDialog]なので、開閉の動き（画面遷移の種類）も
/// 他のダイアログと同じになる。以前（2026-11-02〜）はペイン内の`Stack`に重ねる
/// `PaneModalPopup`だったが、開閉の動きがうまく揃わず、ダイアログへ統一した
/// （広い画面ではサイドバーも暗幕で覆われる）。
///
/// 背景の暗幕をタップすると閉じる。大きさは画面の約7割（最大560×640）。[wide]は約9割（最大960×800）。面はUIスタイルに
/// 合わせる（影は使わない）。呼び出し元のプロバイダーの範囲（使い方ガイドの練習用の画面
/// など）は[UncontrolledProviderScope]で引き継ぐ。
Future<T?> showAlbumDetailPopup<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool wide = false,
  ValueListenable<double?>? widthOverride,
}) {
  final container = ProviderScope.containerOf(context);
  return showAppDialog<T>(
    context: context,
    builder: (dialogContext) => UncontrolledProviderScope(
      container: container,
      child: _PopupSurface(
        wide: wide,
        widthOverride: widthOverride,
        child: Builder(builder: builder),
      ),
    ),
  );
}

class _PopupSurface extends ConsumerWidget {
  const _PopupSurface({
    required this.child,
    required this.wide,
    this.widthOverride,
  });

  final Widget child;

  /// 中身が決めるポップアップの幅（nullの間は[wide]の既定の大きさ）。マークダウンのノートが、
  /// 本文の幅（半角77字）に合わせて開いた後に知らせる（2026-11-06）。画面の9割は超えない。
  final ValueListenable<double?>? widthOverride;

  /// 広めの大きさ（ノートのように、編集や描画で広さが要る中身用）。
  final bool wide;

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
      AppUiStyle.block => DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(BlockTheme.radius),
          boxShadow: BlockTheme.shadow(
            Theme.of(context).colorScheme.primary,
            Theme.of(context).brightness,
          ),
        ),
        child: Material(
          color: Theme.of(context).colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(BlockTheme.radius),
            side: BorderSide(
              color: BlockTheme.lineColor(Theme.of(context).brightness),
              width: BlockTheme.borderWidth,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: child,
        ),
      ),
      _ => Material(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: child,
      ),
    };
    final defaultMaxWidth = wide ? 960.0 : 560.0;
    Widget sized(double maxWidth) => Center(
      child: FractionallySizedBox(
        widthFactor: wide ? 0.9 : 0.7,
        heightFactor: wide ? 0.9 : 0.7,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: maxWidth,
            maxHeight: wide ? 800 : 640,
          ),
          child: surface,
        ),
      ),
    );
    final override = widthOverride;
    if (override == null) return sized(defaultMaxWidth);
    // 幅の変化はなめらかに（開いた直後に本文の幅へ縮む）。
    return ValueListenableBuilder<double?>(
      valueListenable: override,
      builder: (context, value, _) => TweenAnimationBuilder<double>(
        tween: Tween(end: value ?? defaultMaxWidth),
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        builder: (context, width, _) => sized(width),
      ),
    );
  }
}
