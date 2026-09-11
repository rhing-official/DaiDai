import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';
import '../../models/app_ui_style.dart';
import '../../providers/app_ui_style_provider.dart';
import '../../providers/repository_providers.dart';
import '../../utils/fullwidth_digits_formatter.dart';
import '../../widgets/glass/glass_dialog.dart';

/// 新しい6桁パスコードを2回入力させ、一致すればその値を返すダイアログ
/// （2026-09-11追加）。設定＞アプリケーションの「パスコードロック」有効化・
/// 「パスコードを変更」から呼ぶ。実際の保存（`PasscodeRepository
/// .setPasscode`）は呼び出し元が行う（ダイアログ自身は値を確定するだけ）。
class PasscodeSetupDialog extends ConsumerStatefulWidget {
  const PasscodeSetupDialog({super.key});

  /// キャンセルされた場合はnull、確定した場合は新しい6桁のパスコードを返す。
  static Future<String?> show(BuildContext context) {
    return showDialog<String>(
      context: context,
      builder: (_) => const PasscodeSetupDialog(),
    );
  }

  @override
  ConsumerState<PasscodeSetupDialog> createState() =>
      _PasscodeSetupDialogState();
}

class _PasscodeSetupDialogState extends ConsumerState<PasscodeSetupDialog> {
  final _controller = TextEditingController();
  String? _firstEntry;
  String? _errorText;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    if (value.length != 6) return;
    final firstEntry = _firstEntry;
    if (firstEntry == null) {
      setState(() {
        _firstEntry = value;
        _errorText = null;
        _controller.clear();
      });
      return;
    }
    if (value == firstEntry) {
      Navigator.of(context).pop(value);
      return;
    }
    setState(() {
      _firstEntry = null;
      _errorText = ref.read(appStringsProvider).passcodeSetupMismatchError;
      _controller.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final isGlass = ref.watch(appUiStyleProvider) == AppUiStyle.glass;
    final title = Text(strings.passcodeSetupTitle);
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _firstEntry == null
              ? strings.passcodeSetupEnterPrompt
              : strings.passcodeSetupConfirmPrompt,
        ),
        const SizedBox(height: 12),
        if (_errorText != null) ...[
          Text(_errorText!, style: const TextStyle(color: Colors.red)),
          const SizedBox(height: 8),
        ],
        TextField(
          controller: _controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          obscureText: true,
          textAlign: TextAlign.center,
          inputFormatters: const [FullwidthDigitsInputFormatter()],
          maxLength: 6,
          onChanged: _onChanged,
        ),
      ],
    );
    final actions = [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(strings.cancel),
      ),
    ];
    return isGlass
        ? GlassAlertDialog(title: title, content: content, actions: actions)
        : AlertDialog(title: title, content: content, actions: actions);
  }
}

/// 現在設定済みのパスコードの入力を求め、一致すればtrueを返すダイアログ
/// （2026-09-11追加）。パスコードの無効化・変更前の本人確認に使う。
class PasscodeVerifyDialog extends ConsumerStatefulWidget {
  const PasscodeVerifyDialog({super.key});

  static Future<bool> show(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => const PasscodeVerifyDialog(),
    );
    return result ?? false;
  }

  @override
  ConsumerState<PasscodeVerifyDialog> createState() =>
      _PasscodeVerifyDialogState();
}

class _PasscodeVerifyDialogState extends ConsumerState<PasscodeVerifyDialog> {
  final _controller = TextEditingController();
  String? _errorText;
  bool _isVerifying = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onChanged(String value) async {
    if (value.length != 6 || _isVerifying) return;
    setState(() {
      _isVerifying = true;
      _errorText = null;
    });
    final correct = await ref
        .read(passcodeRepositoryProvider)
        .verifyPasscode(value);
    if (!mounted) return;
    if (correct) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _isVerifying = false;
      _errorText = ref.read(appStringsProvider).passcodeIncorrectError;
      _controller.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final isGlass = ref.watch(appUiStyleProvider) == AppUiStyle.glass;
    final title = Text(strings.passcodeCurrentPrompt);
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_errorText != null) ...[
          Text(_errorText!, style: const TextStyle(color: Colors.red)),
          const SizedBox(height: 8),
        ],
        TextField(
          controller: _controller,
          autofocus: true,
          enabled: !_isVerifying,
          keyboardType: TextInputType.number,
          obscureText: true,
          textAlign: TextAlign.center,
          inputFormatters: const [FullwidthDigitsInputFormatter()],
          maxLength: 6,
          onChanged: _onChanged,
        ),
      ],
    );
    final actions = [
      TextButton(
        onPressed: () => Navigator.of(context).pop(false),
        child: Text(strings.cancel),
      ),
    ];
    return isGlass
        ? GlassAlertDialog(title: title, content: content, actions: actions)
        : AlertDialog(title: title, content: content, actions: actions);
  }
}
