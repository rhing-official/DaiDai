import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';
import '../../models/app_ui_style.dart';
import '../../providers/app_ui_style_provider.dart';
import '../../providers/repository_providers.dart';
import '../../repositories/auth_repository.dart';
import '../../widgets/glass/glass_dialog.dart';

/// 秘密の質問（3問固定）の設定・変更ダイアログ（2026-09-16追加、パスキー
/// 紛失時の復旧用）。既存の質問文はサーバーに問い合わせても取得できない
/// （`AuthRepository.getSecretQuestionsStatus`は設定済みかどうかのみを返す）
/// ため、既に設定済みの場合も常に空欄から入力し直す。保存すると3問まるごと
/// 置き換わる。
///
/// [show]はtrue（保存完了）/false・null（キャンセル）を返す。
class SecretQuestionsSetupDialog extends ConsumerStatefulWidget {
  const SecretQuestionsSetupDialog({super.key});

  static Future<bool?> show(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (_) => const SecretQuestionsSetupDialog(),
    );
  }

  @override
  ConsumerState<SecretQuestionsSetupDialog> createState() =>
      _SecretQuestionsSetupDialogState();
}

class _SecretQuestionsSetupDialogState
    extends ConsumerState<SecretQuestionsSetupDialog> {
  final _questionControllers = List.generate(3, (_) => TextEditingController());
  final _answerControllers = List.generate(3, (_) => TextEditingController());
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void dispose() {
    for (final c in _questionControllers) {
      c.dispose();
    }
    for (final c in _answerControllers) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _canSave =>
      _questionControllers.every((c) => c.text.trim().isNotEmpty) &&
      _answerControllers.every((c) => c.text.trim().isNotEmpty);

  Future<void> _save(Strings strings) async {
    if (!_canSave) return;
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });
    try {
      final questions = List.generate(
        3,
        (i) => SecretQuestionInput(
          question: _questionControllers[i].text.trim(),
          answer: _answerControllers[i].text.trim(),
        ),
      );
      await ref.read(authRepositoryProvider).setSecretQuestions(questions);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _errorMessage = strings.secretQuestionsSaveError;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final isGlass = ref.watch(appUiStyleProvider) == AppUiStyle.glass;

    final title = Text(strings.secretQuestionsSectionTitle);
    final content = SizedBox(
      width: 340,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(strings.secretQuestionsSectionDescription),
            for (var i = 0; i < 3; i++) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _questionControllers[i],
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: '${strings.secretQuestionsQuestionLabel} ${i + 1}',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _answerControllers[i],
                obscureText: true,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: '${strings.secretQuestionsAnswerLabel} ${i + 1}',
                ),
              ),
            ],
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
            ],
          ],
        ),
      ),
    );
    final actions = [
      TextButton(
        onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
        child: Text(strings.cancel),
      ),
      FilledButton(
        onPressed: (_isSaving || !_canSave) ? null : () => _save(strings),
        child: _isSaving
            ? const SizedBox.shrink()
            : Text(strings.secretQuestionsSaveButton),
      ),
    ];

    return isGlass
        ? GlassAlertDialog(title: title, content: content, actions: actions)
        : AlertDialog(title: title, content: content, actions: actions);
  }
}
