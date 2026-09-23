import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';
import '../../models/app_ui_style.dart';
import '../../providers/app_ui_style_provider.dart';
import '../../providers/repository_providers.dart';
import '../../repositories/auth_repository.dart';
import '../../widgets/glass/glass_dialog.dart';

/// パスキー紛失時の復旧フロー（2026-09-16追加）。サインイン画面の
/// 「パスキーが使えない場合」リンクから開く。Rhing Seedを入力→秘密の質問
/// （3問すべて正解が必要）に回答する2ステップ構成で、成功するとその場で
/// サインインする（以降は`AuthGate`が認証状態の変化を検知して自動的に
/// 画面遷移する）。
///
/// [show]は成功時にtrueを返す。
class PasskeyRecoveryDialog extends ConsumerStatefulWidget {
  const PasskeyRecoveryDialog({super.key});

  static Future<bool?> show(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (_) => const PasskeyRecoveryDialog(),
    );
  }

  @override
  ConsumerState<PasskeyRecoveryDialog> createState() =>
      _PasskeyRecoveryDialogState();
}

class _PasskeyRecoveryDialogState extends ConsumerState<PasskeyRecoveryDialog> {
  final _rhingSeedController = TextEditingController();
  List<TextEditingController> _answerControllers = [];
  PasskeyRecoveryQuestions? _questions;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _rhingSeedController.dispose();
    for (final c in _answerControllers) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _requestQuestions(Strings strings) async {
    final rhingSeed = _rhingSeedController.text
        .trim()
        .toLowerCase()
        .replaceFirst(RegExp(r'^@+'), '');
    if (rhingSeed.isEmpty) return;
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    try {
      final questions = await ref
          .read(authRepositoryProvider)
          .beginPasskeyRecovery(rhingSeed);
      if (!mounted) return;
      setState(() {
        _questions = questions;
        _answerControllers = List.generate(
          questions.questions.length,
          (_) => TextEditingController(),
        );
        _isSubmitting = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _errorMessage = _errorMessageFor(e, strings);
      });
    }
  }

  Future<void> _submitAnswers(Strings strings) async {
    final questions = _questions;
    if (questions == null) return;
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    try {
      await ref
          .read(authRepositoryProvider)
          .finishPasskeyRecovery(
            questions.recoveryId,
            _answerControllers.map((c) => c.text).toList(),
          );
      // この時点で既にsignInWithCustomTokenでサインイン済み。ここで
      // 「新しいパスキーを登録しますか？」を出してから閉じることで、
      // AuthGateがHomeScreenへ切り替わった後で導線を見失わないようにする
      // （このダイアログのshowDialogはルートNavigatorに積まれるため、
      // AuthGate側のサブツリー切り替えとは独立して残り続ける）。
      if (!mounted) return;
      await _offerAddNewPasskey(strings);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _errorMessage = _errorMessageFor(e, strings);
      });
    }
  }

  Future<void> _offerAddNewPasskey(Strings strings) async {
    final isGlass = ref.read(appUiStyleProvider) == AppUiStyle.glass;
    final addNew = await showDialog<bool>(
      context: context,
      builder: (context) {
        final title = Text(strings.passkeyRecoveryAddNewPasskeyTitle);
        final content = Text(strings.passkeyRecoveryAddNewPasskeyDescription);
        final actions = [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(strings.passkeyRecoveryAddNewPasskeyConfirmButton),
          ),
        ];
        return isGlass
            ? GlassAlertDialog(title: title, content: content, actions: actions)
            : AlertDialog(title: title, content: content, actions: actions);
      },
    );
    if (addNew != true || !mounted) return;
    try {
      await ref.read(authRepositoryProvider).addPasskeyCredential();
    } catch (_) {
      // 復旧自体は完了しているため、ここでの追加登録の失敗は致命的ではない
      // （設定画面から改めて追加できる）。エラー表示はしない。
    }
  }

  String _errorMessageFor(Object error, Strings strings) {
    if (error is FirebaseFunctionsException) {
      switch (error.code) {
        case 'not-found':
          return strings.passkeyRecoveryErrorNotFound;
        case 'failed-precondition':
          return strings.passkeyRecoveryErrorNoQuestionsConfigured;
        case 'resource-exhausted':
          return strings.passkeyRecoveryErrorLocked;
        case 'invalid-argument':
          return strings.passkeyRecoveryErrorWrongAnswers;
      }
    }
    return strings.passkeyRecoveryErrorGeneric;
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final isGlass = ref.watch(appUiStyleProvider) == AppUiStyle.glass;
    final questions = _questions;

    final title = Text(strings.passkeyRecoveryDialogTitle);
    final content = SizedBox(
      width: 320,
      child: questions == null
          ? _buildRhingSeedStep(strings)
          : _buildAnswerStep(strings, questions),
    );
    final actions = [
      TextButton(
        onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
        child: Text(strings.cancel),
      ),
      FilledButton(
        onPressed: _isSubmitting
            ? null
            : () => questions == null
                  ? _requestQuestions(strings)
                  : _submitAnswers(strings),
        child: _isSubmitting
            ? const SizedBox.shrink()
            : Text(
                questions == null
                    ? strings.passkeyRecoveryDialogNextButton
                    : strings.passkeyRecoveryDialogSubmitButton,
              ),
      ),
    ];

    return isGlass
        ? GlassAlertDialog(title: title, content: content, actions: actions)
        : AlertDialog(title: title, content: content, actions: actions);
  }

  Widget _buildRhingSeedStep(Strings strings) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(strings.passkeyRecoveryDialogRhingSeedDescription),
        const SizedBox(height: 16),
        TextField(
          controller: _rhingSeedController,
          autofocus: true,
          decoration: InputDecoration(
            labelText: strings.passkeySignInDialogRhingSeedLabel,
            prefixText: '@',
          ),
          onSubmitted: _isSubmitting ? null : (_) => _requestQuestions(strings),
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 12),
          Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
        ],
      ],
    );
  }

  Widget _buildAnswerStep(Strings strings, PasskeyRecoveryQuestions questions) {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(strings.passkeyRecoveryDialogAnswerDescription),
          for (var i = 0; i < questions.questions.length; i++) ...[
            const SizedBox(height: 16),
            TextField(
              controller: _answerControllers[i],
              obscureText: true,
              decoration: InputDecoration(labelText: questions.questions[i]),
              onSubmitted: (_) =>
                  _isSubmitting ? null : _submitAnswers(strings),
            ),
          ],
          if (_errorMessage != null) ...[
            const SizedBox(height: 12),
            Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
          ],
        ],
      ),
    );
  }
}
