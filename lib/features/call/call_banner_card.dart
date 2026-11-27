import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';
import '../../models/app_ui_style.dart';
import '../../providers/app_ui_style_provider.dart';
import '../../theme/block/block_theme.dart';
import '../../theme/chalk/chalk_theme.dart';
import '../../theme/gekiga/gekiga_colors.dart';
import '../../theme/kinari/kinari_theme.dart';
import '../../widgets/chalk_banner.dart';
import '../../widgets/glass/glass_surface.dart';
import '../../widgets/kinari_surface.dart';

/// 通話の着信バナー（広場の通話開始・一対の着信）の共通の見た目（2026-10-23）。
/// 左に丸いアイコン（右下に通話/ビデオの小さなバッジ）、右に広場名・相手の呼び名、
/// 末尾に、左が赤の拒否・右が緑の応答（広場は参加）の丸いボタン（2026-11-12、以前は×だけで、
/// 本体のタップで応答していた）。本体のタップでは何もしない。
/// 色は`ChatTaskBanner`（`task_banner.dart`）と同じ規則: 劇画は固定の白黒、
/// フラット・ガラスはアクセントカラー地に`onPrimary`。ガラスはぼかし・半透明・縁の
/// 光彩だけを重ねる。影は使わない。
class CallBannerCard extends ConsumerWidget {
  const CallBannerCard({
    required this.avatarBuilder,
    required this.isVideo,
    required this.titleBuilder,
    required this.onAccept,
    required this.onDecline,
    super.key,
  });

  /// 丸いアイコン（半径20）。引数は文字・縁の色。
  final Widget Function(Color foreground) avatarBuilder;
  final bool isVideo;

  /// 広場名・呼び名。引数は太字・文字色を設定済みのスタイル。
  final Widget Function(TextStyle style) titleBuilder;

  /// 応答（広場は参加）。nullの間（応答の処理中）は押せない。
  final VoidCallback? onAccept;

  /// 拒否（広場は閉じるだけ）。
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final uiStyle = ref.watch(appUiStyleProvider);
    final isGekiga = uiStyle == AppUiStyle.gekiga;
    final isGlass = uiStyle == AppUiStyle.glass;
    // 版画・チョーク・生成り・フラットは、アクセントカラーで塗らず、面の色に文字色で描き、
    // 各スタイルの線・箱で囲む（2026-11-27）。ガラスは従来どおりアクセントカラーの塗り。
    final chalk = isChalkTheme(context);
    final kinari = isKinariTheme(context);
    final block = isBlockTheme(context) && !chalk;
    final flat = uiStyle == AppUiStyle.flat && !chalk && !kinari && !block;
    final plain = chalk || kinari || block || flat;
    final background = isGekiga
        ? GekigaColors.panel
        : plain
        ? (block && Theme.of(context).brightness == Brightness.light
              ? Colors.white
              : colorScheme.surface)
        : colorScheme.primary;
    final foreground = isGekiga
        ? GekigaColors.onPanel
        : plain
        ? colorScheme.onSurface
        : colorScheme.onPrimary;
    final radius = isGekiga ? BorderRadius.zero : BorderRadius.circular(12);

    final strings = ref.watch(appStringsProvider);
    // 濃い赤・濃い緑に白（明るい色に白文字は禁止、CLAUDE.md）。UIスタイルには追従しない固定色。
    Widget circleButton({
      required Color color,
      required IconData icon,
      required String tooltip,
      required VoidCallback? onPressed,
    }) => Padding(
      padding: const EdgeInsets.only(left: 8),
      // バナーはNavigatorの外（`MaterialApp.builder`）にありOverlayが無いので、Tooltipは使えない。
      child: Semantics(
        button: true,
        label: tooltip,
        child: Material(
          color: onPressed == null ? color.withValues(alpha: 0.5) : color,
          shape: const CircleBorder(
            side: BorderSide(color: Colors.white, width: 1.5),
          ),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: SizedBox(
              width: 44,
              height: 44,
              child: Icon(icon, color: Colors.white),
            ),
          ),
        ),
      ),
    );
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
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
          circleButton(
            color: Colors.red.shade700,
            icon: Icons.call_end,
            tooltip: strings.callDeclineButton,
            onPressed: onDecline,
          ),
          circleButton(
            color: Colors.green.shade700,
            icon: isVideo ? Icons.videocam : Icons.call,
            tooltip: strings.callAnswerButton,
            onPressed: onAccept,
          ),
        ],
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
    // `Material`は`borderRadius`と`shape`を同時に指定出来ない。
    if (isGekiga) {
      return Material(
        color: background,
        shape: Border.all(color: GekigaColors.onPanel, width: 3),
        child: content,
      );
    }
    if (chalk) {
      // 下の内容が透けると読めないので、黒板の色で塗る。
      return ChalkBannerFrame(
        color: background,
        margin: EdgeInsets.zero,
        radius: 12,
        child: content,
      );
    }
    if (kinari) return KinariBannerFrame(child: content);
    if (block) {
      return DecoratedBox(
        decoration: framedCardDecoration(
          context,
          borderRadius: radius,
          color: background,
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: Material(type: MaterialType.transparency, child: content),
        ),
      );
    }
    if (flat) {
      return Material(
        color: background,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: colorScheme.primary, width: 1.5),
        ),
        child: content,
      );
    }
    return Material(color: background, borderRadius: radius, child: content);
  }
}
