import '../../providers/account_switcher_providers.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';
import '../../providers/repository_providers.dart';
import '../../repositories/auth_repository.dart';
import '../../utils/fullwidth_digits_formatter.dart';
import '../../utils/totp_clipboard_autofill.dart';
import '../../utils/platform_info.dart';
import '../../widgets/branded_block_button.dart';
import '../../widgets/fixed_font_theme.dart';
import '../../widgets/google_sign_in_button.dart';
import 'passkey_recovery_dialog.dart';
import 'passkey_sign_in_dialog.dart';
import 'qr_login_dialog.dart';
import 'qr_login_panel.dart';
import 'saved_accounts_sign_in.dart';
import 'scan_qr_login_dialog.dart';

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({this.popup = false, super.key});

  /// trueなら、全画面ではなく中央のポップアップ（カード）で出す。アカウントの追加の途中
  /// （別のアカウントにログインして保存する間）に使う（2026-11-11）。
  final bool popup;

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen>
    with TotpClipboardAutofill<SignInScreen> {
  bool _isSigningIn = false;
  String? _errorMessage;

  /// Google/Appleでのサインインが2段階認証を要求してきた場合にセットされる
  /// （2026-08-09追加）。セットされている間は通常のログインボタンではなく
  /// コード入力画面を表示する。
  MultiFactorResolver? _resolver;
  final _codeController = TextEditingController();

  @override
  TextEditingController get totpCodeController => _codeController;

  @override
  bool get totpAutofillActive => _resolver != null && !_isSigningIn;

  @override
  void onTotpAutofilled(String code) =>
      _confirmTwoFactorCode(ref.read(appStringsProvider));

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
        _errorMessage = ref.read(appStringsProvider).signInFailedTemplate(e);
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSigningIn = false;
        });
        // 2段階認証の入力欄が出た直後に、クリップボードの6桁を確認する。
        if (_resolver != null) checkTotpClipboard();
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
            : strings.signInFailedTemplate(e.message ?? e.code);
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
    if (widget.popup) return _buildPopup(context, colorScheme, strings);
    return FixedFontTheme(
      child: Scaffold(
        body: Center(
          child: SingleChildScrollView(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // コンピューターで幅が十分あれば、左に他のログイン方法を縦に並べ、
                // 右にQRコードを表示する2列にする（2026-11-06）。
                final twoColumn =
                    resolver == null &&
                    classifyDevice(context) == DeviceClass.computer &&
                    constraints.maxWidth >= 760;
                if (twoColumn) {
                  return _buildComputerLayout(context, colorScheme, strings);
                }
                return ConstrainedBox(
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
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  /// アカウントの追加の途中のログイン（2026-11-11）。今のアカウントはサインアウト済みで
  /// 背後に見せる画面が無いため、暗い背景の上に中央のカードを出す。×で追加をやめる。
  Widget _buildPopup(
    BuildContext context,
    ColorScheme colorScheme,
    Strings strings,
  ) {
    return FixedFontTheme(
      child: Scaffold(
        backgroundColor: Colors.black54,
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Material(
                color: colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(24),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  children: [
                    SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            strings.switchAccountsAddingBanner,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 24),
                          ..._resolver != null
                              ? _buildTwoFactorChallenge(strings)
                              : _buildSignInButtons(
                                  context,
                                  colorScheme,
                                  compact: true,
                                ),
                        ],
                      ),
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: IconButton(
                        tooltip: strings.switchAccountsCancelAdd,
                        icon: const Icon(Icons.close),
                        onPressed: () async {
                          await ref
                              .read(accountSwitcherProvider)
                              .cancelPendingAdd();
                          ref.invalidate(hasPendingAccountAddProvider);
                        },
                      ),
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

  /// コンピューター用の2列レイアウト。左: ロゴと他のログイン方法（縦並び）、右: QRコード。
  Widget _buildComputerLayout(
    BuildContext context,
    ColorScheme colorScheme,
    Strings strings,
  ) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 820),
      child: Container(
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(40),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: _buildSignInButtons(
                  context,
                  colorScheme,
                  showQrButton: false,
                ),
              ),
            ),
            const SizedBox(width: 24),
            Container(width: 1, height: 360, color: colorScheme.outlineVariant),
            const SizedBox(width: 24),
            SizedBox(
              width: 280,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const QrLoginPanel(autoRefresh: true, showDescription: false),
                  const SizedBox(height: 20),
                  Text(
                    strings.qrLoginDialogTitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    strings.qrLoginDialogDescription,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
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
        inputFormatters: const [FullwidthDigitsInputFormatter()],
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
            ? const SizedBox.shrink()
            : Text(strings.twoFactorChallengeConfirmButton),
      ),
    ];
  }

  List<Widget> _buildSignInButtons(
    BuildContext context,
    ColorScheme colorScheme, {
    bool showQrButton = true,
    bool compact = false,
  }) {
    final strings = ref.watch(appStringsProvider);
    return [
      // 追加の途中のポップアップ（[compact]）は、ロゴ・キャッチコピー・保存済みアカウントを
      // 出さない（保存済みは既に切り替えられる）。
      if (!compact) ...[
        Text(
          'DaiDai',
          style: TextStyle(
            fontSize: 40,
            fontWeight: FontWeight.bold,
            color: colorScheme.primary,
          ),
        ),
        const SizedBox(height: 8),
        Text(strings.signInTagline),
        const SizedBox(height: 32),
        const SavedAccountsSignIn(),
      ],
      if (_errorMessage != null) ...[
        Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
        const SizedBox(height: 16),
      ],
      GoogleSignInButton(
        loading: _isSigningIn,
        onPressed: () => _signIn((repo) => repo.signInWithGoogle()),
      ),
      // Appleでのログインは、Apple Developer Program（有料）側でのService ID/
      // 秘密鍵の設定が済むまで実際には使えない為、その設定を行うまでUIから
      // 非表示にしている。AuthRepository.signInWithApple()自体は実装済みなので、
      // 設定が完了したらボタンを復活させるだけでよい。
      // Rhing Seed＋パスキー（WebAuthn）でのログイン・新規アカウント作成
      // （2026-09-16追加）。Linuxはパスキー非対応のため導線ごと出さない
      // （`isPasskeyCapablePlatform`参照、当面Google/Appleログインのみ）。
      // パスキーのボタンはGoogleのすぐ下に置く（2026-11-06）。
      if (isPasskeyCapablePlatform) ...[
        const SizedBox(height: 12),
        BrandedBlockButton(
          onPressed: _isSigningIn
              ? null
              : () => PasskeySignInDialog.show(context),
          icon: const Icon(Icons.key),
          label: strings.passkeySignInButton,
        ),
      ],
      if (showQrButton) ...[
        const SizedBox(height: 12),
        BrandedBlockButton(
          onPressed: () => QrLoginDialog.show(context),
          icon: const Icon(Icons.qr_code_scanner),
          label: strings.qrLoginDialogTitle,
        ),
      ],
      // ログイン済み端末が表示したQRを、この端末で読み取ってログインする経路
      // （2026-10-15追加）。カメラが使えないプラットフォームでは出さない。
      if (isQrScanCapablePlatform) ...[
        const SizedBox(height: 12),
        BrandedBlockButton(
          onPressed: () => startScanQrLogin(context, strings),
          icon: const Icon(Icons.qr_code_2),
          label: strings.qrScanLoginButton,
        ),
      ],
      if (isPasskeyCapablePlatform) ...[
        const SizedBox(height: 20),
        const Divider(),
        const SizedBox(height: 8),
        // 「パスキーが使えない場合」を先に、アカウント作成を後に置く（2026-11-06）。
        TextButton(
          onPressed: _isSigningIn
              ? null
              : () => PasskeyRecoveryDialog.show(context),
          child: Text(strings.passkeyRecoveryLinkLabel),
        ),
        const SizedBox(height: 4),
        TextButton(
          onPressed: _isSigningIn
              ? null
              : () => _signIn((repo) => repo.registerWithPasskey()),
          child: Text(strings.passkeyCreateAccountButton),
        ),
      ],
    ];
  }
}
