import 'package:flutter/material.dart';

/// ペイン（カレンダー・アルバム等、メッセージ画面の上に重ねて開く画面）の
/// キー操作（Escで閉じる等）の受け口（2026-10-13）。`Focus(autofocus: true)`は
/// その時点で他にフォーカスがあると取れないため、開いた直後（描画後）にも
/// 明示的にフォーカスを取り直す。ペイン内の入力欄等が既にフォーカスを持つ場合は
/// 奪わない。
class PaneKeyFocus extends StatefulWidget {
  const PaneKeyFocus({
    required this.onKeyEvent,
    required this.child,
    super.key,
  });

  final FocusOnKeyEventCallback onKeyEvent;
  final Widget child;

  @override
  State<PaneKeyFocus> createState() => _PaneKeyFocusState();
}

class _PaneKeyFocusState extends State<PaneKeyFocus> {
  final _node = FocusNode(debugLabel: 'PaneKeyFocus');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_node.hasFocus) _node.requestFocus();
    });
  }

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _node,
      autofocus: true,
      onKeyEvent: widget.onKeyEvent,
      child: widget.child,
    );
  }
}
