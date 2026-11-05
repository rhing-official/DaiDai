import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/app_ui_style.dart';
import '../../providers/app_ui_style_provider.dart';
import 'gekiga_panel_box.dart';

/// 設定の1行（2026-11-05）。フラット・ガラスは通常の`ListTile`、劇画は他の設定項目と同じ
/// 黒いブロック（ギザギザの枠付き）で描く。項目ごとに劇画の分岐を書かなくても、
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
    return ListTile(
      contentPadding: contentPadding,
      leading: leading,
      title: title,
      subtitle: subtitle,
      trailing: trailing,
      enabled: enabled,
      onTap: onTap,
    );
  }
}
