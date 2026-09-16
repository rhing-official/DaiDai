import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';
import '../../models/app_ui_style.dart';
import '../../providers/app_ui_style_provider.dart';
import '../../providers/repository_providers.dart';
import '../../widgets/glass/glass_dialog.dart';

/// Rhing ID＋パスキー（WebAuthn）でのログイン（2026-09-16追加）。
/// `qr_login_dialog.dart`と同系統の見た目。Rhing IDを入力して確定すると
/// `AuthRepository.signInWithPasskey`を呼び、デバイスにパスキー認証を
/// 要求する。成功すればダイアログを閉じ、以降は`AuthGate`が認証状態の変化を
/// 検知して自動的に画面遷移する。
class PasskeySignInDialog extends ConsumerStatefulWidget {
  const PasskeySignInDialog({super.key});

  static Future<bool?> show(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (_) => const PasskeySignInDialog(),
    );
  }

  @override
  ConsumerState<PasskeySignInDialog> createState() =>
      _PasskeySignInDialogState();
}

class _PasskeySignInDialogState extends ConsumerState<PasskeySignInDialog> {
  final _rhingIdController = TextEditingController();
  bool _isSigningIn = false;
  String? _errorMessage;

  @override
  void dispose() {
    _rhingIdController.dispose();
    super.dispose();
  }

  Future<void> _submit(Strings strings) async {
    final rhingId = _rhingIdController.text.trim();
    if (rhingId.isEmpty) return;
    setState(() {
      _isSigningIn = true;
      _errorMessage = null;
    });
    try {
      await ref.read(authRepositoryProvider).signInWithPasskey(rhingId);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSigningIn = false;
        _errorMessage = strings.passkeySignInDialogError;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final isGlass = ref.watch(appUiStyleProvider) == AppUiStyle.glass;

    final title = Text(strings.passkeySignInButton);
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(strings.passkeySignInDialogDescription),
        const SizedBox(height: 16),
        TextField(
          controller: _rhingIdController,
          autofocus: true,
          decoration: InputDecoration(
            labelText: strings.passkeySignInDialogRhingIdLabel,
          ),
          onSubmitted: _isSigningIn ? null : (_) => _submit(strings),
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 12),
          Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
        ],
      ],
    );
    final actions = [
      TextButton(
        onPressed: _isSigningIn ? null : () => Navigator.of(context).pop(),
        child: Text(strings.cancel),
      ),
      FilledButton(
        onPressed: _isSigningIn ? null : () => _submit(strings),
        child: _isSigningIn
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(strings.passkeySignInDialogSubmitButton),
      ),
    ];

    return isGlass
        ? GlassAlertDialog(title: title, content: content, actions: actions)
        : AlertDialog(title: title, content: content, actions: actions);
  }
}
