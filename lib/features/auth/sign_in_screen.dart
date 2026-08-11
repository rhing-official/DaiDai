import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';
import '../../providers/repository_providers.dart';
import '../../repositories/auth_repository.dart';
import 'qr_login_dialog.dart';

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  bool _isSigningIn = false;
  String? _errorMessage;

  /// Google/Appleでのサインインが2段階認証を要求してきた場合にセットされる
  /// （2026-08-09追加）。セットされている間は通常のログインボタンではなく
  /// コード入力画面を表示する。
  MultiFactorResolver? _resolver;
  final _codeController = TextEditingController();

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _signIn(Future<dynamic> Function(AuthRepository) signIn) async {
    setState(() {
      _isSigningIn = true;
      _errorMessage = null;
    });
    try {
      await signIn(ref.read(authRepositoryProvider));
    } on FirebaseAuthMultiFactorException catch (e) {
      setState(() {
        _resolver = e.resolver;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'ログインに失敗しました: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSigningIn = false;
        });
      }
    }
  }

  Future<void> _confirmTwoFactorCode(Strings strings) async {
    final resolver = _resolver;
    if (resolver == null) return;
    setState(() {
      _isSigningIn = true;
      _errorMessage = null;
    });
    try {
      final assertion = await TotpMultiFactorGenerator.getAssertionForSignIn(
        resolver.hints.first.uid,
        _codeController.text.trim(),
      );
      await resolver.resolveSignIn(assertion);
    } on FirebaseAuthException catch (e) {
      setState(() {
        _errorMessage = e.code == 'invalid-verification-code'
            ? strings.twoFactorInvalidCodeError
            : 'ログインに失敗しました: ${e.message}';
      });
    } finally {
      if (mounted) {
        setState(() => _isSigningIn = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final resolver = _resolver;
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: resolver != null
                  ? _buildTwoFactorChallenge(strings)
                  : _buildSignInButtons(context, colorScheme),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildTwoFactorChallenge(Strings strings) {
    return [
      Text(
        strings.twoFactorChallengeTitle,
        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 8),
      Text(strings.twoFactorChallengeDescription),
      const SizedBox(height: 24),
      if (_errorMessage != null) ...[
        Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
        const SizedBox(height: 16),
      ],
      TextField(
        controller: _codeController,
        keyboardType: TextInputType.number,
        maxLength: 6,
        decoration: InputDecoration(labelText: strings.twoFactorCodeLabel),
        onSubmitted: _isSigningIn
            ? null
            : (_) => _confirmTwoFactorCode(strings),
      ),
      const SizedBox(height: 8),
      ElevatedButton(
        onPressed: _isSigningIn ? null : () => _confirmTwoFactorCode(strings),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
        ),
        child: _isSigningIn
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Text(strings.twoFactorChallengeConfirmButton),
      ),
    ];
  }

  List<Widget> _buildSignInButtons(
    BuildContext context,
    ColorScheme colorScheme,
  ) {
    final strings = ref.watch(appStringsProvider);
    return [
      Text(
        'DaiDai',
        style: TextStyle(
          fontSize: 40,
          fontWeight: FontWeight.bold,
          color: colorScheme.primary,
        ),
      ),
      const SizedBox(height: 8),
      const Text('整う、守る、私に馴染む。'),
      const SizedBox(height: 32),
      if (_errorMessage != null) ...[
        Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
        const SizedBox(height: 16),
      ],
      ElevatedButton(
        onPressed: _isSigningIn
            ? null
            : () => _signIn((repo) => repo.signInWithGoogle()),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
        ),
        child: _isSigningIn
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Text('Googleでログイン'),
      ),
      // Appleでのログインは、Apple Developer Program（有料）側でのService ID/
      // 秘密鍵の設定が済むまで実際には使えないため、その設定を行うまでUIから
      // 非表示にしている。AuthRepository.signInWithApple()自体は実装済みなので、
      // 設定が完了したらボタンを復活させるだけでよい。
      const SizedBox(height: 12),
      TextButton.icon(
        onPressed: () => QrLoginDialog.show(context),
        icon: const Icon(Icons.qr_code_scanner),
        label: Text(strings.qrLoginDialogTitle),
      ),
    ];
  }
}
