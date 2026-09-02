import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/strings.dart';
import '../../models/app_ui_style.dart';
import '../../providers/app_ui_style_provider.dart';
import '../../providers/repository_providers.dart';
import '../../widgets/glass/glass_dialog.dart';

/// 広場からの退会確認ダイアログ。確認後、退会してホームへ戻る。
class GroupLeaveDialog extends ConsumerStatefulWidget {
  const GroupLeaveDialog({
    required this.groupId,
    required this.userId,
    super.key,
  });

  final String groupId;
  final String userId;

  static Future<void> show(
    BuildContext context, {
    required String groupId,
    required String userId,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => GroupLeaveDialog(groupId: groupId, userId: userId),
    );
  }

  @override
  ConsumerState<GroupLeaveDialog> createState() => _GroupLeaveDialogState();
}

class _GroupLeaveDialogState extends ConsumerState<GroupLeaveDialog> {
  bool _leaving = false;
  String? _errorMessage;

  Future<void> _leave() async {
    setState(() {
      _leaving = true;
      _errorMessage = null;
    });
    try {
      await ref
          .read(groupRepositoryProvider)
          .leaveGroup(groupId: widget.groupId, userId: widget.userId);
      if (!mounted) return;
      Navigator.of(context).pop();
      context.go('/');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _leaving = false;
        _errorMessage = e is StateError
            ? e.message
            : '${ref.read(appStringsProvider).profileSaveError}: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final isGlass = ref.watch(appUiStyleProvider) == AppUiStyle.glass;

    final title = Text(strings.groupLeaveConfirmTitle);
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(strings.groupLeaveConfirmMessage),
        if (_errorMessage != null) ...[
          const SizedBox(height: 8),
          Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
        ],
      ],
    );
    final actions = [
      TextButton(
        onPressed: _leaving ? null : () => Navigator.of(context).pop(),
        child: Text(strings.cancel),
      ),
      FilledButton(
        onPressed: _leaving ? null : _leave,
        style: FilledButton.styleFrom(
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
        child: _leaving
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(strings.groupLeaveButton),
      ),
    ];

    return isGlass
        ? GlassAlertDialog(title: title, content: content, actions: actions)
        : AlertDialog(title: title, content: content, actions: actions);
  }
}
