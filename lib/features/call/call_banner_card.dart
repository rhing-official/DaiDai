import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/app_ui_style.dart';
import '../../providers/app_ui_style_provider.dart';
import '../../theme/gekiga/gekiga_colors.dart';
import '../../widgets/glass/glass_surface.dart';

/// 通話の着信バナー（広場の通話開始・一対の着信）の共通の見た目（2026-10-23）。
/// 左に丸いアイコン（右下に通話/ビデオの小さなバッジ）、右に広場名・相手の呼び名、
/// 末尾に×（状態の文言は出さない、2026-10-23）。バナー本体のタップで参加・応答し、
/// ×で閉じる（一対では拒否）。「タップして…」の案内文やボタンは置かない。
/// 色は`ChatTaskBanner`（`task_banner.dart`）と同じ規則: 劇画は固定の白黒、
/// フラット・ガラスはアクセントカラー地に`onPrimary`。ガラスはぼかし・半透明・縁の
/// 光彩だけを重ねる。影は使わない。
class CallBannerCard extends ConsumerWidget {
  const CallBannerCard({
    required this.avatarBuilder,
    required this.isVideo,
    required this.titleBuilder,
    required this.onTap,
    required this.onClose,
    super.key,
  });

  /// 丸いアイコン（半径20）。引数は文字・縁の色。
  final Widget Function(Color foreground) avatarBuilder;
  final bool isVideo;

  /// 広場名・呼び名。引数は太字・文字色を設定済みのスタイル。
  final Widget Function(TextStyle style) titleBuilder;
  final VoidCallback? onTap;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final uiStyle = ref.watch(appUiStyleProvider);
    final isGekiga = uiStyle == AppUiStyle.gekiga;
    final isGlass = uiStyle == AppUiStyle.glass;
    final background = isGekiga ? GekigaColors.panel : colorScheme.primary;
    final foreground = isGekiga ? GekigaColors.onPanel : colorScheme.onPrimary;
    final radius = isGekiga ? BorderRadius.zero : BorderRadius.circular(12);

    final content = InkWell(
      borderRadius: radius,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 4, 14),
        child: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                avatarBuilder(foreground),
                Positioned(
                  right: -8,
                  bottom: -8,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: background,
                      shape: BoxShape.circle,
                      border: Border.all(color: foreground, width: 1.5),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        isVideo ? Icons.videocam : Icons.call,
                        size: 12,
                        color: foreground,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 16),
            Expanded(
              child: titleBuilder(
                TextStyle(
                  color: foreground,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),
            IconButton(
              icon: Icon(Icons.close, color: foreground),
              onPressed: onClose,
            ),
          ],
        ),
      ),
    );

    if (isGlass) {
      return GlassSurface(
        variant: GlassVariant.floating,
        borderRadius: radius,
        fillColorOverride: background,
        child: Material(type: MaterialType.transparency, child: content),
      );
    }
    // `Material`は`borderRadius`と`shape`を同時に指定できない。
    if (isGekiga) {
      return Material(
        color: background,
        shape: Border.all(color: GekigaColors.onPanel, width: 3),
        child: content,
      );
    }
    return Material(color: background, borderRadius: radius, child: content);
  }
}
