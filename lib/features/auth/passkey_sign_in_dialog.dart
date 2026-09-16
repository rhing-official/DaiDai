import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';
import '../../models/app_ui_style.dart';
import '../../providers/app_ui_style_provider.dart';
import '../../providers/repository_providers.dart';
import '../../repositories/auth_repository.dart';
import '../../widgets/glass/glass_dialog.dart';

/// Rhing ID＋パスキー（WebAuthn）でのログイン（2026-09-16追加）。
/// `qr_login_dialog.dart`と同系統の見た目。Rhing IDを入力して確定すると
/// `AuthRepository.signInWithPasskey`を呼び、デバイスにパスキー認証を
/// 要求する。成功すればダイアログを閉じ、以降は`AuthGate`が認証状態の変化を
/// 検知して自動的に画面遷移する。
///
/// Web版かつブラウザがConditional Mediation（パスワードマネージャーの
/// 自動候補表示）に対応していれば、ダイアログを開いた時点で裏側で
/// `AuthRepository.trySignInWithConditionalPasskey`も並行して開始する
/// （2026-09-16追加）。Rhing IDを一切入力せずブラウザ側の候補をタップする
/// だけでログインできるようにするための導線で、対応していない環境では
/// 何も起こらず、これまで通りRhing IDを入力して「ログイン」ボタンを押す
/// 流れになる。
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
  late final AuthRepository _authRepository = ref.read(authRepositoryProvider);
  bool _isSigningIn = false;
  String? _errorMessage;
  bool _conditionalAttemptStarted = false;

  @override
  void initState() {
    super.initState();
    _tryConditionalSignIn();
  }

  Future<void> _tryConditionalSignIn() async {
    if (!await _authRepository.isConditionalPasskeyAvailable()) return;
    if (!mounted) return;
    _conditionalAttemptStarted = true;
    try {
      final user = await _authRepository.trySignInWithConditionalPasskey();
      if (!mounted || user == null) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      // バックグラウンドでの試行のため失敗してもエラー表示はしない。
      // ユーザーはRhing ID入力欄からいつも通りログインできる。
    }
  }

  @override
  void dispose() {
    if (_conditionalAttemptStarted) {
      _authRepository.cancelConditionalPasskeyAttempt();
    }
    _rhingIdController.dispose();
    super.dispose();
  }

  Future<void> _submit(Strings strings) async {
    final rhingId = _rhingIdController.text.trim().toLowerCase().replaceFirst(
      RegExp(r'^@+'),
      '',
    );
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
        _errorMessage = _errorMessageFor(e, strings);
      });
    }
  }

  String _errorMessageFor(Object error, Strings strings) {
    if (error is FirebaseFunctionsException) {
      switch (error.code) {
        case 'not-found':
          return strings.passkeySignInDialogErrorNotFound;
        case 'failed-precondition':
          return strings.passkeySignInDialogErrorNoPasskey;
      }
    }
    return strings.passkeySignInDialogError;
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
          // 'webauthn'は、対応ブラウザ（Web版）でこの欄にパスキー候補の
          // 自動候補を表示させるための標準トークン
          // （https://www.w3.org/TR/webauthn-3/#input-autofill）。
          autofillHints: const [AutofillHints.username, 'webauthn'],
          decoration: InputDecoration(
            labelText: strings.passkeySignInDialogRhingIdLabel,
            prefixText: '@',
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
