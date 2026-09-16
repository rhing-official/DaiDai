import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_ui_style.dart';
import '../providers/app_ui_style_provider.dart';

/// 削除・退会等の危険な操作を示すタップ可能なラベル（ハンバーガーメニュー
/// 項目、設定画面の行等）向けの、角丸のピル＋白文字表示（2026-08-31追加）。
/// 単に文字色だけを`Colors.red`/`colorScheme.error`にする従来のスタイルは
/// 背景に埋もれて視認性が低い上、`colorScheme.error`はダークテーマ下で
/// 明るいサーモンピンクになりさらに読みにくくなる（CLAUDE.md記載）ため、
/// 削除確認ダイアログの確定ボタンと同じ固定の濃い赤（`Colors.red.shade700`）
/// を背景に敷き、白文字を乗せる。劇画UIのみ黒に切り替える（2026-09-16追加、
/// 劇画は背景色自体をユーザーが自由な色に変更できる仕様のため、赤系の
/// 背景色を選ぶと赤ピルが背景に埋もれて視認できなくなる不具合の修正。
/// 黒なら劇画の背景プリセットのどの色とも衝突しない）。
class DestructiveLabel extends ConsumerWidget {
  const DestructiveLabel(
    this.label, {
    this.style,
    this.centered = false,
    super.key,
  });

  final String label;
  final TextStyle? style;

  /// trueなら赤ピルを行全体の中央に置く（既定は他の項目と揃う左寄せ）。
  final bool centered;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isGekiga = ref.watch(appUiStyleProvider) == AppUiStyle.gekiga;
    return Align(
      alignment: centered ? Alignment.center : Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isGekiga ? Colors.black : Colors.red.shade700,
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
