import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/settings_expansion_provider.dart';

/// 設定タブの1カテゴリ内に置く「詳細設定」等の折りたたみブロック。
/// 見出しをタップすると[AnimatedSize]で中身をスライド開閉する
/// （2026-08-13追加、既存のUIには折りたたみ表現が無かったため新規実装）。
class SettingsAccordionSection extends ConsumerStatefulWidget {
  const SettingsAccordionSection({
    required this.title,
    required this.children,
    this.initiallyExpanded = false,
    this.stateKey,
    super.key,
  });

  final String title;
  final List<Widget> children;

  /// 最初から開いた状態にするか（作り直されるまでの初期値のみ）。
  final bool initiallyExpanded;

  /// 指定すると、開閉を[settingsExpansionProvider]に覚え、別のカテゴリへ移って戻っても保つ。
  final String? stateKey;

  @override
  ConsumerState<SettingsAccordionSection> createState() =>
      _SettingsAccordionSectionState();
}

class _SettingsAccordionSectionState
    extends ConsumerState<SettingsAccordionSection> {
  late bool _localExpanded = widget.initiallyExpanded;

  bool get _expanded {
    final key = widget.stateKey;
    if (key == null) return _localExpanded;
    return ref
        .watch(settingsExpansionProvider)
        .expandedOr(key, widget.initiallyExpanded);
  }

  void _toggle() {
    final key = widget.stateKey;
    if (key == null) {
      setState(() => _localExpanded = !_localExpanded);
    } else {
      final now = ref
          .read(settingsExpansionProvider)
          .expandedOr(key, widget.initiallyExpanded);
      ref.read(settingsExpansionProvider.notifier).set(key, !now);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: _toggle,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                AnimatedRotation(
                  turns: _expanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: const Icon(Icons.expand_more),
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          alignment: Alignment.topCenter,
          child: ClipRect(
            child: Align(
              alignment: Alignment.topCenter,
              heightFactor: _expanded ? 1 : 0,
              child: IgnorePointer(
                ignoring: !_expanded,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: widget.children,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
