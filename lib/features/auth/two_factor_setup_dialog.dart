import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../l10n/strings.dart';
import '../../providers/repository_providers.dart';

/// 2段階認証（TOTP）の登録ダイアログ。QRコード（`GroupInviteDialog`と同じ
/// `qr_flutter`）＋手入力用シークレットキーを表示し、認証アプリに表示された
/// 6桁のコードで確定する（2026-08-09追加）。秘密鍵の生成・検証はFirebase
/// Authentication側が行うため、このダイアログはUIのみを担う。
///
/// [show]はtrue（登録完了）/false・null（キャンセル）を返す。
class TwoFactorSetupDialog extends ConsumerStatefulWidget {
  const TwoFactorSetupDialog({required this.rhingId, super.key});

  final String rhingId;

  static Future<bool?> show(BuildContext context, String rhingId) {
    return showDialog<bool>(
      context: context,
      builder: (_) => TwoFactorSetupDialog(rhingId: rhingId),
    );
  }

  @override
  ConsumerState<TwoFactorSetupDialog> createState() =>
      _TwoFactorSetupDialogState();
}

class _TwoFactorSetupDialogState extends ConsumerState<TwoFactorSetupDialog> {
  final _codeController = TextEditingController();
  late Future<({TotpSecret secret, String qrCodeUrl})> _setupFuture;
  bool _isConfirming = false;
  bool _isReauthenticating = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _setupFuture = _startEnrollment();
  }

  Future<({TotpSecret secret, String qrCodeUrl})> _startEnrollment() async {
    final secret = await ref.read(authRepositoryProvider).startTotpEnrollment();
    final qrCodeUrl = await secret.generateQrCodeUrl(
      accountName: widget.rhingId,
      issuer: 'DaiDai',
    );
    return (secret: secret, qrCodeUrl: qrCodeUrl);
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  // Web版のfirebase_authプラグインでは、multiFactor関連の一部エラーが
  // FirebaseAuthException型に正しくマッピングされず素のExceptionとして
  // 飛んでくることがあるため、型チェックに加えてメッセージ文字列でも
  // requires-recent-loginを判定する（2026-08-09、実機で確認した挙動）。
  bool _isRequiresRecentLogin(Object error) {
    if (error is FirebaseAuthException &&
        error.code == 'requires-recent-login') {
      return true;
    }
    return error.toString().contains('requires-recent-login');
  }

  Future<void> _reauthenticateAndRetry() async {
    setState(() => _isReauthenticating = true);
    try {
      await ref.read(authRepositoryProvider).reauthenticate();
      if (!mounted) return;
      setState(() {
        _setupFuture = _startEnrollment();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = '$e');
    } finally {
      if (mounted) setState(() => _isReauthenticating = false);
    }
  }

  Future<void> _confirm(TotpSecret secret, Strings strings) async {
    setState(() {
      _isConfirming = true;
      _errorMessage = null;
    });
    try {
      await ref
          .read(authRepositoryProvider)
          .confirmTotpEnrollment(
            secret: secret,
            oneTimeCode: _codeController.text.trim(),
            displayName: 'TOTP',
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        _errorMessage = _isRequiresRecentLogin(e)
            ? strings.twoFactorRequiresRecentLoginError
            : strings.twoFactorInvalidCodeError;
      });
    } finally {
      if (mounted) setState(() => _isConfirming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    return AlertDialog(
      title: Text(strings.twoFactorSetupDialogTitle),
      content: SizedBox(
        width: 320,
        child: FutureBuilder<({TotpSecret secret, String qrCodeUrl})>(
          future: _setupFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const SizedBox(
                height: 120,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (snapshot.hasError) {
              final error = snapshot.error!;
              if (_isRequiresRecentLogin(error)) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(strings.twoFactorRequiresRecentLoginError),
                    const SizedBox(height: 16),
                    Center(
                      child: _isReauthenticating
                          ? const CircularProgressIndicator()
                          : FilledButton(
                              onPressed: _reauthenticateAndRetry,
                              child: Text(
                                strings.twoFactorReauthenticateButton,
                              ),
                            ),
                    ),
                  ],
                );
              }
              return Text('$error', style: const TextStyle(color: Colors.red));
            }
            final secret = snapshot.data!.secret;
            final qrCodeUrl = snapshot.data!.qrCodeUrl;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(strings.twoFactorSetupDescription),
                const SizedBox(height: 16),
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                    child: QrImageView(data: qrCodeUrl, size: 180),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  strings.twoFactorSecretKeyLabel,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                SelectableText(
                  secret.secretKey,
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _codeController,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  decoration: InputDecoration(
                    labelText: strings.twoFactorCodeLabel,
                    errorText: _errorMessage,
                  ),
                  onSubmitted: _isConfirming
                      ? null
                      : (_) => _confirm(secret, strings),
                ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(strings.cancel),
        ),
        FilledButton(
          onPressed: _isConfirming
              ? null
              : () async {
                  final setup = await _setupFuture;
                  if (!mounted) return;
                  await _confirm(setup.secret, strings);
                },
          child: _isConfirming
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(strings.twoFactorEnrollButton),
        ),
      ],
    );
  }
}
