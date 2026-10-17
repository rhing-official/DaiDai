import 'package:flutter/material.dart';

/// [AppDropdown]の選択肢1件。
class AppDropdownItem<T> {
  const AppDropdownItem({required this.value, required this.label});

  final T value;
  final String label;
}

/// ラベル付きのプルダウン（2026-10-17追加）。Googleフォームのプルダウンを参考に、
/// 選択中の項目を入力欄に重ねて上下へ展開し、少しだけ浮いた見た目（影）で
/// 表示する。展開しても本文はずれない（標準の`DropdownButton`のメニュー）。
/// 標準のままだとメニューの色が背景（劇画UIの赤など）と同化して見えにくかった
/// ため、メニューの地色は入力欄と同じ塗り（`InputDecorationTheme`）に固定する。
class AppDropdown<T> extends StatelessWidget {
  const AppDropdown({
    required this.label,
    required this.items,
    required this.value,
    required this.onChanged,
    this.placeholder = '',
    this.enabled = true,
    super.key,
  });

  /// 入力欄のラベル。
  final String label;
  final List<AppDropdownItem<T>> items;

  /// 選択中の値。どの項目にも一致しなければ[placeholder]を出す。
  final T? value;
  final ValueChanged<T> onChanged;

  /// 未選択時に入力欄へ出す文言。
  final String placeholder;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final menuColor =
        theme.inputDecorationTheme.fillColor ??
        theme.colorScheme.surfaceContainerHighest;
    final hasSelection = items.any((item) => item.value == value);
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        // 下線は入力欄の枠で足りるため出さない。
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          isExpanded: true,
          value: hasSelection ? value : null,
          hint: Text(placeholder),
          dropdownColor: menuColor,
          // 少しだけ浮いて見える影。
          elevation: 4,
          borderRadius: BorderRadius.circular(8),
          items: [
            for (final item in items)
              DropdownMenuItem<T>(value: item.value, child: Text(item.label)),
          ],
          onChanged: enabled ? (v) => onChanged(v as T) : null,
        ),
      ),
    );
  }
}
