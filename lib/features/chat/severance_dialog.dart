import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';
import '../../providers/repository_providers.dart';

/// 絶縁（双方合意による友達関係の解消・会話履歴の完全削除）の確認ダイアログ。
/// 提案する側（[SeveranceDialogMode.propose]）・同意する側
/// （[SeveranceDialogMode.accept]）の両方で使う（表示文言と確定時の呼び出し先
/// リポジトリメソッドが異なるだけで、UI構造は共通）。
enum SeveranceDialogMode { propose, accept }

class SeveranceDialog extends ConsumerStatefulWidget {
  const SeveranceDialog({
    required this.mode,
    required this.dmId,
    required this.currentUserId,
    required this.otherUserId,
    super.key,
  });

  final SeveranceDialogMode mode;
  final String dmId;
  final String currentUserId;
  final String otherUserId;

  static Future<void> show(
    BuildContext context, {
    required SeveranceDialogMode mode,
    required String dmId,
    required String currentUserId,
    required String otherUserId,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => SeveranceDialog(
        mode: mode,
        dmId: dmId,
        currentUserId: currentUserId,
        otherUserId: otherUserId,
      ),
    );
  }

  @override
  ConsumerState<SeveranceDialog> createState() => _SeveranceDialogState();
}

class _SeveranceDialogState extends ConsumerState<SeveranceDialog> {
  bool _submitting = false;
  String? _errorMessage;

  bool get _isPropose => widget.mode == SeveranceDialogMode.propose;

  Future<void> _confirm() async {
    setState(() {
      _submitting = true;
      _errorMessage = null;
    });
    try {
      final repository = ref.read(directMessageRepositoryProvider);
      if (_isPropose) {
        await repository.proposeSeverance(
          dmId: widget.dmId,
          userId: widget.currentUserId,
        );
      } else {
        await repository.acceptSeverance(
          dmId: widget.dmId,
          currentUserId: widget.currentUserId,
          otherUserId: widget.otherUserId,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _errorMessage = '${ref.read(appStringsProvider).profileSaveError}: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);

    return AlertDialog(
      title: Text(
        _isPropose
            ? strings.severanceProposeDialogTitle
            : strings.severanceAcceptDialogTitle,
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _isPropose
                ? strings.severanceProposeDialogMessage
                : strings.severanceAcceptDialogMessage,
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 8),
            Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: Text(strings.cancel),
        ),
        FilledButton(
          onPressed: _submitting ? null : _confirm,
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
          child: _submitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(
                  _isPropose
                      ? strings.severanceProposeButton
                      : strings.severanceAcceptButton,
                ),
        ),
      ],
    );
  }
}
