import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:passkeys/types.dart';

import '../../l10n/strings.dart';
import '../../models/app_ui_style.dart';
import '../../providers/app_ui_style_provider.dart';
import '../../providers/repository_providers.dart';
import '../../repositories/auth_repository.dart';
import '../../widgets/glass/glass_dialog.dart';
import '../../widgets/dialog_keyboard_shortcuts.dart';

/// Rhing Seed＋パスキー（WebAuthn）でのログイン（2026-09-16追加）。
/// `qr_login_dialog.dart`と同系統の見た目。Rhing Seedを入力して確定すると
/// `AuthRepository.signInWithPasskey`を呼び、デバイスにパスキー認証を
/// 要求する。成功すればダイアログを閉じ、以降は`AuthGate`が認証状態の変化を
/// 検知して自動的に画面遷移する。
///
/// Web版では、ダイアログを開いた時点で自動的にパスキー選択ポップアップ
/// （ブラウザ/パスワードマネージャーのモーダル）を出す（2026-10-11追加）。
/// Rhing Seedを入力せずそのまま候補を選べば、ログインできる。ポップアップを
/// 閉じた場合はダイアログに留まり、続けてConditional Mediation（Rhing Seed
/// 入力欄に出るオートフィル候補）の待機に切り替える。Seedを入力して
/// 「ログイン」を押す従来の流れもそのまま使える。モーダルとConditionalは
/// 同時に走らせられないため直列にしている。
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
  final _rhingSeedController = TextEditingController();
  late final AuthRepository _authRepository = ref.read(authRepositoryProvider);
  bool _isSigningIn = false;
  String? _errorMessage;
  bool _conditionalAttemptStarted = false;

  @override
  void initState() {
    super.initState();
    _tryAutoPrompt();
  }

  Future<void> _tryAutoPrompt() async {
    if (!kIsWeb) return;
    _conditionalAttemptStarted = true;
    try {
      await _authRepository.signInWithDiscoverablePasskey();
      if (!mounted) return;
      Navigator.of(context).pop(true);
      return;
    } on PasskeyAuthCancelledException {
      // ポップアップを閉じた・Seed入力などで中断された場合。ダイアログに留まる。
    } on NoCredentialsAvailableException {
      // この端末に使えるパスキーが無い場合も、Seed入力へ進める。
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _errorMessage = _errorMessageFor(e, ref.read(appStringsProvider)),
      );
    }
    // 「ログイン」ボタンによる中断だった場合は、そちらの処理を優先する。
    if (!mounted || _isSigningIn) return;
    await _tryConditionalSignIn();
  }

  Future<void> _tryConditionalSignIn() async {
    if (!await _authRepository.isConditionalPasskeyAvailable()) return;
    if (!mounted) return;
    try {
      final user = await _authRepository.trySignInWithConditionalPasskey();
      if (!mounted || user == null) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      // バックグラウンドでの試行のため失敗してもエラー表示はしない。
      // ユーザーはRhing Seed入力欄からいつも通りログインできる。
    }
  }

  @override
  void dispose() {
    if (_conditionalAttemptStarted) {
      _authRepository.cancelConditionalPasskeyAttempt();
    }
    _rhingSeedController.dispose();
    super.dispose();
  }

  Future<void> _submit(Strings strings) async {
    final rhingSeed = _rhingSeedController.text
        .trim()
        .toLowerCase()
        .replaceFirst(RegExp(r'^@+'), '');
    setState(() {
      _isSigningIn = true;
      _errorMessage = null;
    });
    try {
      // 裏で待機中のモーダル/Conditional試行と競合しないよう先に中断する。
      if (_conditionalAttemptStarted) {
        await _authRepository.cancelConditionalPasskeyAttempt();
      }
      if (rhingSeed.isEmpty) {
        // Seed空欄: パスキー選択モーダルから選ぶ方式（2026-10-04追加）。
        await _authRepository.signInWithDiscoverablePasskey();
      } else {
        await _authRepository.signInWithPasskey(rhingSeed);
      }
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
          controller: _rhingSeedController,
          autofocus: true,
          // 'webauthn'は、対応ブラウザ（Web版）でこの欄にパスキー候補の
          // 自動候補を表示させるための標準トークン
          // （https://www.w3.org/TR/webauthn-3/#input-autofill）。
          autofillHints: const [AutofillHints.username, 'webauthn'],
          decoration: InputDecoration(
            labelText: strings.passkeySignInDialogRhingSeedLabel,
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
            ? const SizedBox.shrink()
            : Text(strings.passkeySignInDialogSubmitButton),
      ),
    ];

    return isGlass
        ? GlassAlertDialog(title: title, content: content, actions: actions)
        : KeyboardAlertDialog(title: title, content: content, actions: actions);
  }
}
