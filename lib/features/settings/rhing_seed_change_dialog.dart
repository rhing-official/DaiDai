import '../../services/app_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../l10n/strings.dart';
import '../../models/app_ui_style.dart';
import '../../providers/app_locale_provider.dart';
import '../../providers/app_ui_style_provider.dart';
import '../../providers/repository_providers.dart';
import '../../utils/reserved_rhing_seeds.dart';
import '../../utils/rhing_seed_format.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/dialog_keyboard_shortcuts.dart';
import '../../widgets/glass/glass_dialog.dart';

/// Rhing Seedを変更するダイアログ（設定＞アカウント、2026-11-07）。
/// 変更は100日に1回までで、変更前のSeedは60日間予約され旧招待リンクは新Seedへ
/// 転送される（サーバー側の本体は`functions/src/rhingSeedChange.ts`）。
/// 変更できた場合はtrueを返す。
class RhingSeedChangeDialog extends ConsumerStatefulWidget {
  const RhingSeedChangeDialog({
    required this.userId,
    required this.currentSeed,
    super.key,
  });

  final String userId;
  final String currentSeed;

  static Future<bool?> show(
    BuildContext context, {
    required String userId,
    required String currentSeed,
  }) {
    return showAppDialog<bool>(
      context: context,
      builder: (_) =>
          RhingSeedChangeDialog(userId: userId, currentSeed: currentSeed),
    );
  }

  @override
  ConsumerState<RhingSeedChangeDialog> createState() =>
      _RhingSeedChangeDialogState();
}

class _RhingSeedChangeDialogState extends ConsumerState<RhingSeedChangeDialog> {
  final _controller = TextEditingController();

  /// 次に変更できる日時。変更できる状態ならnull。
  DateTime? _nextChangeAt;
  bool _loadingNextChange = true;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadNextChange();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadNextChange() async {
    DateTime? next;
    try {
      next = await ref
          .read(userRepositoryProvider)
          .getRhingSeedNextChangeAt(widget.userId);
    } catch (_) {
      // 取得できなくても入力は出来る（最終判定はサーバー）。
    }
    if (!mounted) return;
    setState(() {
      _nextChangeAt = next;
      _loadingNextChange = false;
    });
  }

  Future<void> _submit() async {
    final strings = ref.read(appStringsProvider);
    final seed = _controller.text.trim();
    if (!rhingSeedPattern.hasMatch(seed)) {
      setState(() => _errorMessage = strings.rhingSeedSetupInvalidError);
      return;
    }
    if (seed.toLowerCase() == widget.currentSeed.toLowerCase()) {
      setState(() => _errorMessage = strings.rhingSeedChangeSameError);
      return;
    }
    if (isReservedRhingSeed(seed)) {
      setState(() => _errorMessage = strings.rhingSeedSetupTakenError);
      return;
    }
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    try {
      await ref.read(userRepositoryProvider).changeRhingSeed(seed);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on AppFunctionsException catch (e) {
      if (!mounted) return;
      if (e.code == 'already-exists') {
        setState(() => _errorMessage = strings.rhingSeedSetupTakenError);
      } else if (e.code == 'failed-precondition') {
        // 間隔の制限。サーバーの最終変更日時を読み直して日付付きで案内する。
        await _loadNextChange();
        if (!mounted) return;
        setState(() => _errorMessage = null);
      } else {
        setState(
          () => _errorMessage = strings.rhingSeedChangeFailedTemplate(
            e.message ?? e.code,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = strings.rhingSeedChangeFailedTemplate(e));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final isGlass = ref.watch(appUiStyleProvider) == AppUiStyle.glass;
    final localeCode = ref.watch(appLocaleProvider).languageCode;
    final nextChangeAt = _nextChangeAt;
    final blocked = nextChangeAt != null;

    final title = Text(strings.settingsRhingSeedChange);
    final content = SizedBox(
      width: 360,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(strings.rhingSeedChangeNotice),
          const SizedBox(height: 8),
          Text(strings.rhingSeedSetupRules),
          const SizedBox(height: 16),
          if (blocked)
            Text(
              strings.rhingSeedChangeTooSoonTemplate(
                DateFormat.yMMMd(localeCode).format(nextChangeAt),
              ),
            )
          else
            TextField(
              controller: _controller,
              autofocus: true,
              maxLength: 20,
              enabled: !_loadingNextChange && !_isSubmitting,
              decoration: InputDecoration(
                labelText: strings.rhingSeedChangeNewLabel,
                prefixText: '@',
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (_) => _submit(),
            ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 8),
            Text(_errorMessage!, style: TextStyle(color: Colors.red.shade700)),
          ],
        ],
      ),
    );
    final actions = [
      TextButton(
        onPressed: _isSubmitting
            ? null
            : () => Navigator.of(context).pop(false),
        child: Text(strings.cancel),
      ),
      if (!blocked)
        // 後戻りしにくい確定ボタンは濃い赤＋白文字に統一する（CLAUDE.md）。
        FilledButton(
          onPressed: (_loadingNextChange || _isSubmitting) ? null : _submit,
          style: FilledButton.styleFrom(
            backgroundColor: Colors.red.shade700,
            foregroundColor: Colors.white,
          ),
          child: Text(strings.rhingSeedChangeSubmit),
        ),
    ];
    return isGlass
        ? GlassAlertDialog(title: title, content: content, actions: actions)
        : KeyboardAlertDialog(title: title, content: content, actions: actions);
  }
}
