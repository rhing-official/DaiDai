import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 削除・退会等の危険な操作を示すタップ可能なラベル（ハンバーガーメニュー
/// 項目、設定画面の行等）向けの、角丸のピル＋白文字表示（2026-08-31追加）。
/// 単に文字色だけを`Colors.red`/`colorScheme.error`にする従来のスタイルは
/// 背景に埋もれて視認性が低い上、`colorScheme.error`はダークテーマ下で
/// 明るいサーモンピンクになりさらに読みにくくなる（CLAUDE.md記載）ため、
/// 削除確認ダイアログの確定ボタンと同じ固定の濃い赤（`Colors.red.shade700`）
/// を背景に敷き、白文字を乗せる。劇画UIは一時期黒に切り替えていた（2026-09-16追加、
/// 劇画は背景色自体をユーザーが自由な色に変更できる仕様のため、赤系の
/// 背景色を選ぶと赤ピルが背景に埋もれて視認できなくなる不具合の修正。
/// 2026-10-11に全スタイル共通の赤へ戻した。白縁は付けない）。
class DestructiveLabel extends ConsumerWidget {
  const DestructiveLabel(
    this.label, {
    this.style,
    this.centered = false,
    this.alignTextWithSiblings = false,
    this.enabled = true,
    super.key,
  });

  final String label;
  final TextStyle? style;

  /// trueなら赤ピルを行全体の中央に置く（既定は他の項目と揃う左寄せ）。
  final bool centered;

  /// trueなら、ピルを左へそのパディング分ずらし、**文字の左端**を隣の項目の
  /// 文字と揃える（2026-10-10追加）。既定ではピルの左端が揃うため、文字は
  /// パディング分右にずれて見える。[centered]がfalseの時のみ有効。
  final bool alignTextWithSiblings;

  /// falseなら赤ピルを半透明にして、無効（グレーアウト）に見せる。`ListTile`の
  /// `enabled: false`は文字色しか薄めず、固定の赤塗りには効かないため。
  final bool enabled;

  static const _horizontalPadding = 10.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pillBox = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: _horizontalPadding,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: Colors.red.shade700,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: (style ?? const TextStyle()).copyWith(color: Colors.white),
      ),
    );
    final pill = enabled ? pillBox : Opacity(opacity: 0.38, child: pillBox);
    return Align(
      alignment: centered ? Alignment.center : Alignment.centerLeft,
      child: alignTextWithSiblings && !centered
          ? Transform.translate(
              offset: const Offset(-_horizontalPadding, 0),
              child: pill,
            )
          : pill,
    );
  }
}
