import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/strings.dart';
import '../../providers/repository_providers.dart';

/// 広場を丸ごと削除する確認ダイアログ（長のみ、2026-08-02追加）。
/// `GroupLeaveDialog`と同じ構成。確認後、削除してホームへ戻る。
class GroupDeleteDialog extends ConsumerStatefulWidget {
  const GroupDeleteDialog({
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
      builder: (_) => GroupDeleteDialog(groupId: groupId, userId: userId),
    );
  }

  @override
  ConsumerState<GroupDeleteDialog> createState() => _GroupDeleteDialogState();
}

class _GroupDeleteDialogState extends ConsumerState<GroupDeleteDialog> {
  bool _deleting = false;
  String? _errorMessage;

  Future<void> _delete() async {
    setState(() {
      _deleting = true;
      _errorMessage = null;
    });
    try {
      await ref
          .read(groupRepositoryProvider)
          .deleteGroup(groupId: widget.groupId, requestedBy: widget.userId);
      if (!mounted) return;
      Navigator.of(context).pop();
      context.go('/');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _deleting = false;
        _errorMessage = e is StateError
            ? e.message
            : '${ref.read(appStringsProvider).profileSaveError}: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);

    return AlertDialog(
      // 横幅いっぱいに広がって縦に詰まって見えないよう幅を制限する
      // （2026-08-12、横幅を縮め縦幅を確保するようユーザー指摘）。
      constraints: const BoxConstraints(maxWidth: 400),
      title: Text(strings.groupDeleteConfirmTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(strings.groupDeleteConfirmMessage),
          if (_errorMessage != null) ...[
            const SizedBox(height: 8),
            Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _deleting ? null : () => Navigator.of(context).pop(),
          child: Text(strings.cancel),
        ),
        FilledButton(
          onPressed: _deleting ? null : _delete,
          // colorScheme.errorはダークテーマ下ではMaterial3の仕様上
          // 明るめのサーモンピンクに近い色になり「濃い赤」に見えなかった
          // ため、固定の濃い赤に変更する（2026-08-12）。
          style: FilledButton.styleFrom(
            backgroundColor: Colors.red.shade700,
            foregroundColor: Colors.white,
          ),
          child: _deleting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(strings.groupDeleteButton),
        ),
      ],
    );
  }
}
