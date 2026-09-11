import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';
import '../../models/app_ui_style.dart';
import '../../providers/app_ui_style_provider.dart';
import '../../providers/passcode_lock_provider.dart';
import '../../providers/repository_providers.dart';
import '../../utils/fullwidth_digits_formatter.dart';
import '../../widgets/glass/glass_dialog.dart';

/// アプリ起動時のパスコードロック画面（2026-09-11追加）。`PasscodeLockGate`
/// からのみ表示される。`sign_in_screen.dart`と同じ、UIスタイル（フラット/
/// 劇画/ガラス）を区別しないシンプルな`Scaffold`構成にしている
/// （`account_suspended_screen.dart`と同じ判断。この画面はテーマの配色・
/// フォントだけで十分で、構造自体を切り替える必要が無いため）。
class PasscodeLockScreen extends ConsumerStatefulWidget {
  const PasscodeLockScreen({super.key});

  @override
  ConsumerState<PasscodeLockScreen> createState() => _PasscodeLockScreenState();
}

/// 連続不正解時のロックアウトしきい値・時間（2026-09-11追加）。
/// ネットワークを介さない端末内認証のため、Firestoreルール等ではなく
/// この画面自身が簡易的なブルートフォース対策として持つ。
const _kMaxFailedAttempts = 5;
const _kLockoutSeconds = 30;

class _PasscodeLockScreenState extends ConsumerState<PasscodeLockScreen> {
  final _codeController = TextEditingController();
  String? _errorMessage;
  bool _isVerifying = false;
  bool _isCheckingBiometrics = true;
  bool _biometricAvailable = false;
  int _failedAttempts = 0;
  int? _lockoutSecondsRemaining;
  Timer? _lockoutTimer;

  @override
  void initState() {
    super.initState();
    _prepareBiometrics();
  }

  @override
  void dispose() {
    _codeController.dispose();
    _lockoutTimer?.cancel();
    super.dispose();
  }

  Future<void> _prepareBiometrics() async {
    final repository = ref.read(passcodeRepositoryProvider);
    final available =
        await repository.isBiometricEnabled() &&
        await repository.canUseBiometrics();
    if (!mounted) return;
    setState(() {
      _biometricAvailable = available;
      _isCheckingBiometrics = false;
    });
    if (available) unawaited(_tryBiometric());
  }

  Future<void> _tryBiometric() async {
    final success = await ref
        .read(passcodeRepositoryProvider)
        .authenticateWithBiometrics();
    if (!mounted || !success) return;
    ref.read(isAppUnlockedProvider.notifier).markUnlocked();
  }

  void _startLockout() {
    _lockoutTimer?.cancel();
    setState(() => _lockoutSecondsRemaining = _kLockoutSeconds);
    _lockoutTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final remaining = (_lockoutSecondsRemaining ?? 1) - 1;
      if (remaining <= 0) {
        timer.cancel();
        setState(() {
          _lockoutSecondsRemaining = null;
          _failedAttempts = 0;
        });
      } else {
        setState(() => _lockoutSecondsRemaining = remaining);
      }
    });
  }

  Future<void> _submitCode(Strings strings) async {
    if (_lockoutSecondsRemaining != null || _isVerifying) return;
    final code = _codeController.text;
    if (code.length != 6) return;
    setState(() {
      _isVerifying = true;
      _errorMessage = null;
    });
    final correct = await ref
        .read(passcodeRepositoryProvider)
        .verifyPasscode(code);
    if (!mounted) return;
    if (correct) {
      ref.read(isAppUnlockedProvider.notifier).markUnlocked();
      return;
    }
    _codeController.clear();
    _failedAttempts++;
    setState(() {
      _isVerifying = false;
      _errorMessage = strings.passcodeIncorrectError;
    });
    if (_failedAttempts >= _kMaxFailedAttempts) _startLockout();
  }

  Future<void> _confirmForgotPasscode(Strings strings) async {
    final isGlass = ref.read(appUiStyleProvider) == AppUiStyle.glass;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final title = Text(strings.passcodeForgotDialogTitle);
        final content = Text(strings.passcodeForgotDialogMessage);
        final actions = [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(strings.passcodeForgotDialogConfirmButton),
          ),
        ];
        return isGlass
            ? GlassAlertDialog(title: title, content: content, actions: actions)
            : AlertDialog(title: title, content: content, actions: actions);
      },
    );
    if (confirmed != true || !mounted) return;
    await ref.read(passcodeRepositoryProvider).clearPasscode();
    if (!mounted) return;
    await ref.read(authRepositoryProvider).signOut();
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final lockedOut = _lockoutSecondsRemaining != null;
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'DaiDai',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      strings.passcodeLockScreenTitle,
                      style: Theme.of(context).textTheme.titleMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    if (lockedOut) ...[
                      Text(
                        strings.passcodeLockoutMessageTemplate(
                          _lockoutSecondsRemaining!,
                        ),
                        style: const TextStyle(color: Colors.red),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                    ] else if (_errorMessage != null) ...[
                      Text(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.red),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                    ],
                    TextField(
                      controller: _codeController,
                      enabled: !lockedOut && !_isVerifying,
                      autofocus: !_isCheckingBiometrics && !_biometricAvailable,
                      keyboardType: TextInputType.number,
                      obscureText: true,
                      textAlign: TextAlign.center,
                      inputFormatters: const [FullwidthDigitsInputFormatter()],
                      maxLength: 6,
                      onChanged: (value) {
                        if (value.length == 6) _submitCode(strings);
                      },
                    ),
                    if (_biometricAvailable) ...[
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: lockedOut ? null : _tryBiometric,
                        child: Text(strings.passcodeLockScreenBiometricButton),
                      ),
                    ],
                    const SizedBox(height: 24),
                    TextButton(
                      onPressed: () => _confirmForgotPasscode(strings),
                      child: Text(strings.passcodeLockScreenForgotButton),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
