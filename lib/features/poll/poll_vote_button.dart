import 'package:flutter/material.dart';

import '../../widgets/gekiga/gekiga_panel_box.dart';

/// 「投票する」「投票を変更」ボタン（メッセージ内の埋め込みカードと詳細ポップアップで
/// 共通、2026-11-08）。選ぶまでは押せない（[onPressed]がnull）が、消さずにグレーアウトして
/// 見せる（劇画・版画では押せない間は背景に溶けて見えなかった）。劇画は他の劇画のボタンと
/// 同じジグザグ枠の[GekigaButton]（押せる時=白地黒文字、押せない間=黒地に薄い文字）、
/// それ以外は[FilledButton]（押せない間は[foreground]の薄い灰色）にする。
/// [foreground]は、置く面の文字色。
class PollVoteButton extends StatelessWidget {
  const PollVoteButton({
    required this.isGekiga,
    required this.foreground,
    required this.onPressed,
    required this.label,
    super.key,
  });

  final bool isGekiga;
  final Color foreground;
  final VoidCallback? onPressed;
  final String label;

  @override
  Widget build(BuildContext context) {
    if (isGekiga) {
      return GekigaJointedTileList(
        seeds: [label.hashCode],
        selectedFlags: [onPressed != null],
        children: [
          GekigaButton(
            label: label,
            selected: onPressed != null,
            onPressed: onPressed,
          ),
        ],
      );
    }
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        disabledBackgroundColor: foreground.withValues(alpha: 0.12),
        disabledForegroundColor: foreground.withValues(alpha: 0.38),
      ),
      child: Text(label),
    );
  }
}
