import 'package:flutter/material.dart';

import '../../models/app_user.dart';

/// 出欠回答・日程調整回答で共通して使う、独立したピル型のチップ
/// （2026-09-04追加、2026-09-05に`calendar_event_detail_dialog.dart`から
/// 切り出して`schedule_coordination_detail_dialog.dart`とも共有）。
/// アクセントカラーは選択中チップの背景の塗りとしてのみ使い、文字・
/// アイコンは`onPrimary`/`onSurfaceVariant`という固定のコントラスト色に
/// する（CLAUDE.md「テキストにアクセントカラーを使わない」規約）。
/// `Theme.of(context).colorScheme`はアクセントカラー・劇画・ガラスいずれの
/// UIスタイルでも既に正しく導出されているため、スタイル別の分岐は不要。
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
class CalendarResponseGroup extends StatelessWidget {
  const CalendarResponseGroup({
    required this.label,
    required this.users,
    required this.conversationId,
    super.key,
  });

  final String label;
  final List<AppUser> users;
  final String conversationId;

  @override
  Widget build(BuildContext context) {
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
              for (final user in users)
                Chip(
                  avatar: CircleAvatar(
                    backgroundImage:
                        user.effectiveIconFor(conversationId)?.url != null
                        ? NetworkImage(
                            user.effectiveIconFor(conversationId)!.url,
                          )
                        : null,
                    child: user.effectiveIconFor(conversationId)?.url == null
                        ? const Icon(Icons.person, size: 14)
                        : null,
                  ),
                  label: Text(
                    user.effectiveNicknameFor(conversationId)?.text ??
                        '@${user.rhingId}',
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
