import 'package:flutter/material.dart';

/// 未読件数バッジ。CLAUDE.mdの配色規約（薄い背景色に白文字禁止）に従い、
/// 濃色のアクセントカラーを背景に使う（2026-09-02追加、2026-10-04に
/// `talks_tab.dart`のprivateクラスから寄合一覧でも使えるよう切り出し）。
class UnreadBadge extends StatelessWidget {
  const UnreadBadge({required this.count, super.key}) : attention = false;

  /// 件数の代わりに「!」を出す（承認待ちの友達申請など、操作や確認が要る印、2026-11-17）。
  const UnreadBadge.attention({super.key}) : count = 0, attention = true;

  final int count;
  final bool attention;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: colorScheme.primary,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        attention ? '!' : (count > 99 ? '99+' : '$count'),
        style: TextStyle(
          color: colorScheme.onPrimary,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
