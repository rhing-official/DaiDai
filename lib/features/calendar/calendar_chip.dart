import '../../providers/contact_alias_providers.dart';
import '../../utils/contact_alias.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/app_ui_style.dart';
import '../../models/app_user.dart';
import '../../providers/app_ui_style_provider.dart';
import '../../theme/block/block_theme.dart';
import '../../theme/gekiga/gekiga_colors.dart';
import '../../widgets/gekiga/gekiga_panel_box.dart';
import '../../widgets/glass/glass_avatar.dart';

/// 出欠回答・日程調整回答で共通して使う、独立したピル型のチップ
/// （2026-09-04追加、2026-09-05に`calendar_event_detail_dialog.dart`から
/// 切り出して`schedule_coordination_detail_dialog.dart`とも共有）。
/// アクセントカラーは選択中チップの背景の塗りとしてのみ使い、文字・
/// アイコンは`onPrimary`/`onSurfaceVariant`という固定のコントラスト色に
/// する（CLAUDE.md「テキストにアクセントカラーを使わない」規約）。
/// `Theme.of(context).colorScheme`はアクセントカラー・劇画・ガラスいずれの
/// UIスタイルでも既に正しく導出されている為、スタイル別の分岐は不要。
Widget calendarChoiceChip(
  BuildContext context, {
  required String label,
  IconData? icon,
  required bool selected,
  required ValueChanged<bool>? onSelected,
}) {
  final colorScheme = Theme.of(context).colorScheme;
  final foreground = selected
      ? colorScheme.onPrimary
      : colorScheme.onSurfaceVariant;
  return ChoiceChip(
    avatar: icon != null ? Icon(icon, size: 16, color: foreground) : null,
    label: Text(label, style: TextStyle(color: foreground)),
    selected: selected,
    onSelected: onSelected,
    showCheckmark: false,
    shape: const StadiumBorder(),
    selectedColor: colorScheme.primary,
    backgroundColor: colorScheme.surfaceContainerHighest,
    side: BorderSide(
      color: selected ? colorScheme.primary : colorScheme.outlineVariant,
    ),
  );
}

/// 回答グループ1件分（見出し＋対象住人のチップ一覧、2026-09-02追加・
/// 2026-09-05に共有化）。対象が0人なら何も描画しない。
class CalendarResponseGroup extends ConsumerWidget {
  const CalendarResponseGroup({
    required this.label,
    required this.users,
    required this.conversationId,
    this.styledMemberChips = false,
    super.key,
  });

  final String label;
  final List<AppUser> users;
  final String conversationId;

  /// メンバーのチップを、劇画（ジグザグ枠の黒い箱）・版画（太枠と硬い影の箱）では
  /// そのスタイルのデザインにする（2026-11-08、投票の詳細ダイアログで指定）。
  /// falseなら従来どおり標準の`Chip`（予定・日程調整のダイアログ）。
  final bool styledMemberChips;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (users.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label (${users.length})',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final user in users) _memberChip(context, ref, user),
            ],
          ),
        ],
      ),
    );
  }

  /// 自分が指定した呼び名があれば優先する（2026-11-06）。
  String _displayName(WidgetRef ref, AppUser user) => resolveDisplayName(
    alias: aliasOf(ref.watch(myContactAliasesProvider).value, user.userId),
    nickname: user.effectiveNicknameFor(conversationId)?.text,
    rhingSeed: user.rhingSeed,
  );

  Widget _memberChip(BuildContext context, WidgetRef ref, AppUser user) {
    final uiStyle = ref.watch(appUiStyleProvider);
    final iconUrl = user.effectiveIconFor(conversationId)?.url;
    final name = _displayName(ref, user);
    final onSurfaceVariant = Theme.of(context).colorScheme.onSurfaceVariant;

    if (styledMemberChips && uiStyle == AppUiStyle.gekiga) {
      // 他の劇画のボタン・タイルと同じ、モノクロの枠の黒い箱（白文字・白縁のアイコン）。
      return GekigaJointedTileList(
        seeds: [user.userId.hashCode],
        selectedFlags: const [false],
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: GekigaColors.onPanel, width: 1.5),
                  ),
                  child: CircleAvatar(
                    radius: 11,
                    backgroundColor: GekigaColors.panel,
                    backgroundImage: iconUrl != null
                        ? NetworkImage(iconUrl)
                        : null,
                    child: iconUrl == null
                        ? const Icon(
                            Icons.person,
                            size: 14,
                            color: GekigaColors.onPanel,
                          )
                        : null,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  name,
                  style: const TextStyle(
                    color: GekigaColors.onPanel,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    if (styledMemberChips && uiStyle == AppUiStyle.block) {
      // 版画の枠付きの箱（黒の太枠＋硬い影）。影が右・下へはみ出す分の余白を足す。
      return Padding(
        padding: const EdgeInsets.only(right: 3, bottom: 3),
        child: blockMaterialBox(
          context,
          radius: 18,
          shadowOffset: const Offset(2, 2),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 4, 12, 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 12,
                  backgroundImage: iconUrl != null
                      ? NetworkImage(iconUrl)
                      : null,
                  child: iconUrl == null
                      ? const Icon(Icons.person, size: 14)
                      : null,
                ),
                const SizedBox(width: 8),
                Text(name),
              ],
            ),
          ),
        ),
      );
    }

    return Chip(
      avatar: uiStyle == AppUiStyle.glass
          ? GlassAvatar(
              size: 28,
              image: iconUrl != null ? NetworkImage(iconUrl) : null,
              fallback: iconUrl != null
                  ? null
                  : Icon(Icons.person, size: 14, color: onSurfaceVariant),
            )
          : CircleAvatar(
              backgroundImage: iconUrl != null ? NetworkImage(iconUrl) : null,
              child: iconUrl == null
                  ? const Icon(Icons.person, size: 14)
                  : null,
            ),
      label: Text(name),
    );
  }
}
