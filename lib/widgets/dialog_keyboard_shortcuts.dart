import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// ダイアログをキーボードだけで操作できるようにする（2026-10-11追加）。
///
/// - Enter / テンキーのEnter: 同意。[actions]のうち最後のFilledButton／
///   ElevatedButton（無ければ最後のボタン）の`onPressed`を実行する。
/// - Backspace / Delete: 拒否。ダイアログを結果なし（null）で閉じる。
///   バリア（外側）タップで閉じた時と同じ結果になる。
///
/// 次の場合は何もせず、元々のキー操作に任せる:
/// - テキスト入力欄にフォーカスがある時（Backspace/Deleteは文字削除、Enterは
///   入力欄の`onSubmitted`が確定を担当している。二重に閉じてしまうのを防ぐ）
/// - いずれかのボタンにフォーカスがある時のEnter（Tabで「キャンセル」へ移動
///   してからEnterを押した場合に、意図せず同意になるのを防ぐ）
class DialogKeyboardShortcuts extends StatefulWidget {
  const DialogKeyboardShortcuts({
    required this.actions,
    required this.child,
    super.key,
  });

  final List<Widget>? actions;
  final Widget child;

  @override
  State<DialogKeyboardShortcuts> createState() =>
      _DialogKeyboardShortcutsState();

  static VoidCallback? _confirmCallback(List<Widget>? actions) {
    if (actions == null) return null;
    VoidCallback? primary;
    VoidCallback? fallback;
    for (final action in actions) {
      if (action is! ButtonStyleButton) continue;
      final onPressed = action.onPressed;
      if (onPressed == null) continue;
      fallback = onPressed;
      if (action is FilledButton || action is ElevatedButton) {
        primary = onPressed;
      }
    }
    return primary ?? fallback;
  }

  static bool _isInTextInput(FocusNode? node) {
    final context = node?.context;
    if (context == null) return false;
    if (context.widget is EditableText) return true;
    var found = false;
    context.visitAncestorElements((element) {
      if (element.widget is EditableText) {
        found = true;
        return false;
      }
      return true;
    });
    return found;
  }

  static bool _isInButton(FocusNode? node) {
    final context = node?.context;
    if (context == null) return false;
    if (context.widget is ButtonStyleButton) return true;
    var found = false;
    context.visitAncestorElements((element) {
      if (element.widget is ButtonStyleButton) {
        found = true;
        return false;
      }
      return true;
    });
    return found;
  }
}

class _DialogKeyboardShortcutsState extends State<DialogKeyboardShortcuts> {
  final _node = FocusNode(debugLabel: 'DialogKeyboardShortcuts');

  @override
  void initState() {
    super.initState();
    // 入力欄の`autofocus`を奪わないよう、フォーカス解決後も誰もダイアログ内に
    // フォーカスしていない時だけ、キー入力の受け皿としてフォーカスを取る。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (!_hasFocusedDescendant()) _node.requestFocus();
      });
    });
  }

  bool _hasFocusedDescendant() =>
      _node.descendants.any((n) => n.hasPrimaryFocus);

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _node,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        final primary = FocusManager.instance.primaryFocus;
        if (DialogKeyboardShortcuts._isInTextInput(primary)) {
          return KeyEventResult.ignored;
        }
        if (key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.numpadEnter) {
          if (DialogKeyboardShortcuts._isInButton(primary)) {
            return KeyEventResult.ignored;
          }
          final onPressed = DialogKeyboardShortcuts._confirmCallback(
            widget.actions,
          );
          if (onPressed == null) return KeyEventResult.ignored;
          onPressed();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.backspace ||
            key == LogicalKeyboardKey.delete) {
          Navigator.of(context).pop();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: widget.child,
    );
  }
}

/// [AlertDialog]にキーボード操作（[DialogKeyboardShortcuts]）を足したもの。
/// 既存の`AlertDialog(...)`呼び出しをそのまま差し替えられる。
class KeyboardAlertDialog extends StatelessWidget {
  const KeyboardAlertDialog({
    this.title,
    this.content,
    this.actions,
    this.scrollable = false,
    this.constraints,
    super.key,
  });

  final Widget? title;
  final Widget? content;
  final List<Widget>? actions;
  final bool scrollable;
  final BoxConstraints? constraints;

  @override
  Widget build(BuildContext context) {
    return DialogKeyboardShortcuts(
      actions: actions,
      child: AlertDialog(
        title: title,
        content: content,
        actions: actions,
        scrollable: scrollable,
        constraints: constraints,
      ),
    );
  }
}
