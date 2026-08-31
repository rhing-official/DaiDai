import 'package:flutter/material.dart';

/// 削除・退会等の危険な操作を示すタップ可能なラベル（ハンバーガーメニュー
/// 項目、設定画面の行等）向けの、角丸の赤ピル＋白文字表示（2026-08-31追加）。
/// 単に文字色だけを`Colors.red`/`colorScheme.error`にする従来のスタイルは
/// 背景に埋もれて視認性が低い上、`colorScheme.error`はダークテーマ下で
/// 明るいサーモンピンクになりさらに読みにくくなる（CLAUDE.md記載）ため、
/// 削除確認ダイアログの確定ボタンと同じ固定の濃い赤（`Colors.red.shade700`）
/// を背景に敷き、白文字を乗せる。
class DestructiveLabel extends StatelessWidget {
  const DestructiveLabel(this.label, {this.style, super.key});

  final String label;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.red.shade700,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: (style ?? const TextStyle()).copyWith(color: Colors.white),
        ),
      ),
    );
  }
}
