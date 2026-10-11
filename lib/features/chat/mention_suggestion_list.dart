import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../theme/gekiga/gekiga_colors.dart';
import '../../utils/mention_suggestion.dart';
import '../../widgets/glass/glass_surface.dart';
import '../../widgets/media_preview_frame.dart';

/// `@`入力時に入力欄のすぐ上へ出すメンション候補の縦リスト（2026-10-11追加）。
/// 「メンバー／その他／ロール」の区分見出しで分け、キーボード（↑↓/Enter/Tab）
/// で選んでいる行は[selectedIndex]で強調する。[candidates]の並び順は
/// 呼び出し側の絞り込み結果のままで、区分ごとにまとめて表示する。
///
/// 入力欄・メッセージ領域と同化しないよう、UIスタイルごとの不透明な面
/// （フラット=一段明るい面＋縁線、ガラス=ぼかし＋縁線、劇画=黒の直角ボックス）
/// で包み、周囲に余白を取って「浮いた」独立の面に見せる。マテリアルに影は
/// 使わない方針のため、影ではなく面・縁線・角丸・余白だけで区別する
/// （2026-10-11、ユーザー指示）。
class MentionSuggestionList extends StatelessWidget {
  const MentionSuggestionList({
    required this.candidates,
    required this.selectedIndex,
    required this.onPick,
    required this.strings,
    required this.plazaLabel,
    this.isGlass = false,
    this.isGekiga = false,
    super.key,
  });

  final List<MentionCandidate> candidates;
  final int selectedIndex;
  final void Function(MentionCandidate candidate) onPick;
  final Strings strings;
  final String plazaLabel;
  final bool isGlass;
  final bool isGekiga;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final foreground = isGekiga ? GekigaColors.onPanel : colorScheme.onSurface;
    final mutedForeground = isGekiga
        ? GekigaColors.onPanel.withValues(alpha: 0.7)
        : colorScheme.onSurfaceVariant;
    // `@everyone`は「メンバー」区分の末尾に含める（2026-10-11、ユーザー指示）。
    final sections = <(String, Set<MentionKind>)>[
      (strings.mentionSectionMembers, {MentionKind.user, MentionKind.everyone}),
      (strings.mentionSectionRoles, {MentionKind.role}),
    ];
    final children = <Widget>[];
    // 表示順（区分ごと）でも、キーボードの選択位置は[candidates]の
    // インデックスで管理するため、元のインデックスを保ったまま並べる。
    for (final (title, kinds) in sections) {
      final entries = [
        for (var i = 0; i < candidates.length; i++)
          if (kinds.contains(candidates[i].kind)) (i, candidates[i]),
      ];
      if (entries.isEmpty) continue;
      children.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: mutedForeground),
          ),
        ),
      );
      for (final (index, candidate) in entries) {
        children.add(
          _MentionRow(
            candidate: candidate,
            selected: index == selectedIndex,
            foreground: foreground,
            mutedForeground: mutedForeground,
            description: switch (candidate.kind) {
              MentionKind.user => candidate.subtitle,
              MentionKind.everyone => strings.mentionEveryoneDescription(
                plazaLabel,
              ),
              MentionKind.role => strings.mentionRoleDescription(plazaLabel),
            },
            onTap: () => onPick(candidate),
          ),
        );
      }
    }
    final list = ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 260),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: 4),
        children: children,
      ),
    );
    const radius = BorderRadius.all(Radius.circular(12));
    final Widget panel;
    if (isGekiga) {
      panel = GekigaStraightMonochromeBox(isMe: false, child: list);
    } else if (isGlass) {
      panel = GlassSurface(
        variant: GlassVariant.chrome,
        borderRadius: radius,
        child: list,
      );
    } else {
      panel = DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: radius,
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: ClipRRect(borderRadius: radius, child: list),
      );
    }
    return Padding(padding: const EdgeInsets.all(8), child: panel);
  }
}

class _MentionRow extends StatelessWidget {
  const _MentionRow({
    required this.candidate,
    required this.selected,
    required this.foreground,
    required this.mutedForeground,
    required this.description,
    required this.onTap,
  });

  final MentionCandidate candidate;
  final bool selected;
  final Color foreground;
  final Color mutedForeground;
  final String? description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final roleColor = candidate.color == null
        ? null
        : Color(0xFF000000 | candidate.color!);
    return InkWell(
      onTap: onTap,
      child: Container(
        color: selected
            ? foreground.withValues(alpha: 0.12)
            : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Text(
              candidate.kind == MentionKind.user
                  ? candidate.label
                  : candidate.insertText,
              style: TextStyle(color: roleColor ?? foreground),
            ),
            if (description != null) ...[
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  description!,
                  textAlign: TextAlign.end,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: mutedForeground),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
