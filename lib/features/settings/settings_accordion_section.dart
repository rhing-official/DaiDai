import 'package:flutter/material.dart';

/// 設定タブの1カテゴリ内に置く「詳細設定」等の折りたたみブロック。
/// 見出しをタップすると[AnimatedSize]で中身をスライド開閉する
/// （2026-08-13追加、既存のUIには折りたたみ表現が無かったため新規実装）。
class SettingsAccordionSection extends StatefulWidget {
  const SettingsAccordionSection({
    required this.title,
    required this.children,
    super.key,
  });

  final String title;
  final List<Widget> children;

  @override
  State<SettingsAccordionSection> createState() =>
      _SettingsAccordionSectionState();
}

class _SettingsAccordionSectionState extends State<SettingsAccordionSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
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
