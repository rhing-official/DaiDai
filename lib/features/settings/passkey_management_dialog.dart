import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../l10n/strings.dart';
import '../../models/app_ui_style.dart';
import '../../providers/app_locale_provider.dart';
import '../../providers/app_ui_style_provider.dart';
import '../../providers/repository_providers.dart';
import '../../repositories/auth_repository.dart';
import '../../widgets/glass/glass_dialog.dart';
import 'secret_questions_setup_dialog.dart';

/// パスキーの名前の最大文字数。サーバー側（`normalizePasskeyName`、
/// `functions/src/index.ts`）の`PASSKEY_NAME_MAX_LENGTH`と揃える
/// （2026-09-18追加）。
const _kPasskeyNameMaxLength = 30;

/// 登録済みパスキーの一覧・追加登録・削除と、秘密の質問（復旧手段）の
/// 設定状況をまとめたダイアログ（2026-09-16追加）。設定＞アカウント＞
/// セキュリティの「パスキー」行から開く。
class PasskeyManagementDialog extends ConsumerStatefulWidget {
  const PasskeyManagementDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (_) => const PasskeyManagementDialog(),
    );
  }

  @override
  ConsumerState<PasskeyManagementDialog> createState() =>
      _PasskeyManagementDialogState();
}

class _PasskeyManagementDialogState
    extends ConsumerState<PasskeyManagementDialog> {
  late Future<
    ({
      List<PasskeyCredentialInfo> credentials,
      SecretQuestionsStatus questionsStatus,
    })
  >
  _future;
  bool _isBusy = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<
    ({
      List<PasskeyCredentialInfo> credentials,
      SecretQuestionsStatus questionsStatus,
    })
  >
  _load() async {
    final repo = ref.read(authRepositoryProvider);
    final credentials = await repo.listPasskeyCredentials();
    final questionsStatus = await repo.getSecretQuestionsStatus();
    return (credentials: credentials, questionsStatus: questionsStatus);
  }

  void _reload() {
    setState(() {
      _future = _load();
    });
  }

  Future<void> _addPasskey(Strings strings) async {
    // 追加前に名前を入力させる（2026-09-18追加）。空欄のまま決定した場合は
    // 「名前無し」として扱い、一覧では作成日時にフォールバック表示する
    // （新規アカウント作成時のパスキー作成は一発実行のままこのダイアログを
    // 挟まない、ユーザー確認済みの方針）。
    final name = await _PasskeyNameDialog.show(
      context,
      title: strings.passkeyManagementNameDialogTitle,
    );
    if (name == null || !mounted) return;
    setState(() {
      _isBusy = true;
      _errorMessage = null;
    });
    try {
      await ref
          .read(authRepositoryProvider)
          .addPasskeyCredential(name: name.isEmpty ? null : name);
      if (!mounted) return;
      _reload();
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _errorMessage = _withErrorCode(
          strings.passkeyManagementAddError,
          e,
        ),
      );
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _renamePasskey(
    Strings strings,
    PasskeyCredentialInfo credential,
  ) async {
    final name = await _PasskeyNameDialog.show(
      context,
      title: strings.passkeyManagementNameDialogTitle,
      initialName: credential.name,
    );
    if (name == null || !mounted) return;
    setState(() {
      _isBusy = true;
      _errorMessage = null;
    });
    try {
      await ref
          .read(authRepositoryProvider)
          .renamePasskeyCredential(credential.id, name);
      if (!mounted) return;
      _reload();
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _errorMessage = _withErrorCode(
          strings.passkeyManagementRenameError,
          e,
        ),
      );
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  /// 例外の種類ごとのコード名を[message]の末尾に付記する。ブラウザ層
  /// （`PasskeyAuthenticator().register()`、Web実装は`PlatformException`を
  /// 投げる）由来かCloud Functions層（`FirebaseFunctionsException`）由来かで
  /// 原因が大きく異なるため、固定文言だけでは調査に手がかりが無かった
  /// （2026-09-18追加。本番でRP ID設定がlocalhost固定のままパスキー追加が
  /// 常に失敗していた不具合の調査で必要性が判明した）。
  String _withErrorCode(String message, Object error) {
    final code = switch (error) {
      PlatformException(:final code) => code,
      FirebaseFunctionsException(:final code) => code,
      _ => null,
    };
    return code == null ? message : '$message ($code)';
  }

  Future<void> _deletePasskey(
    Strings strings,
    PasskeyCredentialInfo credential,
    bool isLast,
    bool questionsConfigured,
  ) async {
    final confirmed = await _confirmDeletePasskey(
      context,
      strings,
      isLast && !questionsConfigured,
    );
    if (!confirmed || !mounted) return;
    setState(() {
      _isBusy = true;
      _errorMessage = null;
    });
    try {
      await ref
          .read(authRepositoryProvider)
          .deletePasskeyCredential(credential.id);
      if (!mounted) return;
      _reload();
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _errorMessage = _withErrorCode(
          strings.passkeyManagementDeleteError,
          e,
        ),
      );
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _editSecretQuestions() async {
    final saved = await SecretQuestionsSetupDialog.show(context);
    if (saved == true && mounted) {
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final isGlass = ref.watch(appUiStyleProvider) == AppUiStyle.glass;
    final localeCode = ref.watch(appLocaleProvider).languageCode;
    final dateFormat = DateFormat.yMMMd(localeCode);

    final title = Text(strings.settingsPasskey);
    final content = SizedBox(
      width: 360,
      child: FutureBuilder(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const SizedBox(
              height: 160,
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final credentials = snapshot.data!.credentials;
          final questionsStatus = snapshot.data!.questionsStatus;
          return SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  strings.passkeyManagementListTitle,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                if (credentials.isEmpty)
                  Text(strings.passkeyManagementEmptyMessage)
                else
                  for (final credential in credentials)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      leading: const Icon(Icons.key),
                      title: Text(
                        credential.name ??
                            (credential.createdAt == null
                                ? strings.settingsPasskey
                                : dateFormat.format(credential.createdAt!)),
                      ),
                      subtitle: credential.lastUsedAt == null
                          ? null
                          : Text(dateFormat.format(credential.lastUsedAt!)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit_outlined),
                            tooltip: strings.passkeyManagementRenameTooltip,
                            onPressed: _isBusy
                                ? null
                                : () => _renamePasskey(strings, credential),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: _isBusy
                                ? null
                                : () => _deletePasskey(
                                    strings,
                                    credential,
                                    credentials.length == 1,
                                    questionsStatus.configured,
                                  ),
                          ),
                        ],
                      ),
                    ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: _isBusy ? null : () => _addPasskey(strings),
                  child: Text(strings.passkeyManagementAddButton),
                ),
                const Divider(height: 32),
                Text(
                  strings.secretQuestionsSectionTitle,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                Text(strings.secretQuestionsSectionDescription),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        questionsStatus.configured
                            ? strings.secretQuestionsStatusConfigured
                            : strings.secretQuestionsStatusNotConfigured,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _isBusy ? null : _editSecretQuestions,
                      child: Text(strings.secretQuestionsEditButton),
                    ),
                  ],
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ],
              ],
            ),
          );
        },
      ),
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

/// パスキーの名前を入力・編集するダイアログ（2026-09-18追加）。追加時
/// （[initialName]がnull）・変更時のどちらにも使う。空欄のまま決定すると
/// 「名前無し」（呼び出し元が空文字列を受け取る）として扱われる。
class _PasskeyNameDialog extends ConsumerStatefulWidget {
  const _PasskeyNameDialog({required this.title, this.initialName});

  final String title;
  final String? initialName;

  /// キャンセル時は`null`、決定時は入力文字列（空文字列を含みうる）を返す。
  static Future<String?> show(
    BuildContext context, {
    required String title,
    String? initialName,
  }) {
    return showDialog<String>(
      context: context,
      builder: (_) =>
          _PasskeyNameDialog(title: title, initialName: initialName),
    );
  }

  @override
  ConsumerState<_PasskeyNameDialog> createState() => _PasskeyNameDialogState();
}

class _PasskeyNameDialogState extends ConsumerState<_PasskeyNameDialog> {
  late final _controller = TextEditingController(text: widget.initialName);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.of(context).pop(_controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final isGlass = ref.watch(appUiStyleProvider) == AppUiStyle.glass;
    final title = Text(widget.title);
    final content = TextField(
      controller: _controller,
      autofocus: true,
      maxLength: _kPasskeyNameMaxLength,
      decoration: InputDecoration(
        hintText: strings.passkeyManagementNameDialogHint,
      ),
      onSubmitted: (_) => _submit(),
    );
    final actions = [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(strings.cancel),
      ),
      FilledButton(onPressed: _submit, child: Text(strings.done)),
    ];
    return isGlass
        ? GlassAlertDialog(title: title, content: content, actions: actions)
        : AlertDialog(title: title, content: content, actions: actions);
  }
}

/// パスキー削除の確認ダイアログ。最後の1つを削除しようとしていて、かつ
/// 秘密の質問も未設定の場合は追加の警告を表示する。
Future<bool> _confirmDeletePasskey(
  BuildContext context,
  Strings strings,
  bool showLastCredentialWarning,
) async {
  final isGlass =
      ProviderScope.containerOf(context).read(appUiStyleProvider) ==
      AppUiStyle.glass;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) {
      final title = Text(strings.passkeyManagementDeleteConfirmTitle);
      final content = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(strings.passkeyManagementDeleteConfirmMessage),
          if (showLastCredentialWarning) ...[
            const SizedBox(height: 8),
            Text(
              strings.passkeyManagementLastCredentialWarning,
              style: const TextStyle(color: Colors.red),
            ),
          ],
        ],
      );
      final actions = [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(strings.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          // 大事な選択のボタンは「広場を削除」と同じ固定の濃い赤にする
          // （CLAUDE.md参照、2026-09-16）。
          style: FilledButton.styleFrom(
            backgroundColor: Colors.red.shade700,
            foregroundColor: Colors.white,
          ),
          child: Text(strings.passkeyManagementDeleteConfirmButton),
        ),
      ];
      return isGlass
          ? GlassAlertDialog(title: title, content: content, actions: actions)
          : AlertDialog(title: title, content: content, actions: actions);
    },
  );
  return confirmed ?? false;
}
