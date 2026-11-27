import '../kinari_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/app_ui_style.dart';
import '../../providers/app_ui_style_provider.dart';
import '../../theme/block/block_theme.dart';
import '../glass/glass_surface.dart';
import 'gekiga_panel_box.dart';

/// 設定の1行（2026-11-05）。フラット・ガラスは通常の`ListTile`、劇画は他の設定項目と同じ
/// 黒いブロック（ギザギザの枠付き）で描く。項目毎に劇画の分岐を書かなくても、
/// 設定画面の見た目が揃う。[selected]がtrueなら白地黒文字（選択中の項目）。
class SettingsTile extends ConsumerWidget {
  const SettingsTile({
    super.key,
    this.leading,
    this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.contentPadding,
    this.selected = false,
    this.enabled = true,
  });

  final Widget? leading;
  final Widget? title;
  final Widget? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? contentPadding;
  final bool selected;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(appUiStyleProvider) == AppUiStyle.gekiga) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: GekigaJointedTileList(
          seeds: [Object.hash(title.runtimeType, subtitle == null)],
          selectedFlags: [selected],
          children: [
            GekigaTileContent(
              selected: selected,
              leading: leading,
              title: title ?? const SizedBox.shrink(),
              subtitle: subtitle,
              trailing: trailing,
              onTap: enabled ? onTap : null,
            ),
          ],
        ),
      );
    }
    if (ref.watch(appUiStyleProvider) == AppUiStyle.kinari) {
      // 生成り: 1行が1つのブロック。選択中はアクセントのへこんだ面、他は紙のへこんだ面。
      final scheme = Theme.of(context).colorScheme;
      final fg = selected ? scheme.onPrimary : scheme.onSurface;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: blockFitWidth(
          KinariTileFrame(
            selected: selected,
            child: ListTile(
              contentPadding: contentPadding,
              iconColor: fg,
              textColor: fg,
              leading: leading,
              title: title,
              subtitle: subtitle,
              trailing: trailing,
              enabled: enabled,
              onTap: onTap,
            ),
          ),
        ),
      );
    }
    if (ref.watch(appUiStyleProvider).isBoxed) {
      final scheme = Theme.of(context).colorScheme;
      final fg = selected ? scheme.onPrimary : scheme.onSurface;
      return Padding(
        padding: const EdgeInsets.fromLTRB(2, 4, 6, 8),
        child: blockFitWidth(
          blockMaterialBox(
            context,
            color: selected
                ? scheme.primary
                : (Theme.of(context).brightness == Brightness.light
                      ? Colors.white
                      : scheme.surface),
            child: ListTile(
              contentPadding: contentPadding,
              iconColor: fg,
              textColor: fg,
              leading: leading,
              title: title,
              subtitle: subtitle,
              trailing: trailing,
              enabled: enabled,
              onTap: onTap,
            ),
          ),
        ),
      );
    }
    // フラット・ガラスも、カテゴリ一覧と同じ角丸の箱にする（2026-11-26）。劇画・版画の箱と
    // 同じく、1行が1つのブロックになる。
    final scheme = Theme.of(context).colorScheme;
    if (ref.watch(appUiStyleProvider) == AppUiStyle.glass) {
      // 選択・非選択で文字色は変えない（塗りだけで選択を表す）。
      final fg = scheme.onSurfaceVariant;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        // 箱は文字の幅に合わせる（2026-11-26、全スタイルで統一）。
        child: blockFitWidth(
          GlassSurface(
            borderRadius: BorderRadius.circular(12),
            accentColorOverride: selected ? scheme.primary : null,
            child: Material(
              color: selected
                  ? scheme.primary.withValues(alpha: 0.45)
                  : Colors.transparent,
              child: ListTile(
                contentPadding: contentPadding,
                iconColor: fg,
                textColor: fg,
                leading: leading,
                title: title,
                subtitle: subtitle,
                trailing: trailing,
                enabled: enabled,
                onTap: onTap,
              ),
            ),
          ),
        ),
      );
    }
    final fg = selected ? scheme.onPrimary : scheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: blockFitWidth(
        Material(
          color: selected ? scheme.primary : scheme.surface,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            contentPadding: contentPadding,
            iconColor: fg,
            textColor: fg,
            leading: leading,
            title: title,
            subtitle: subtitle,
            trailing: trailing,
            enabled: enabled,
            onTap: onTap,
          ),
        ),
      ),
    );
  }
}
