import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';
import '../../models/app_ui_style.dart';
import '../../models/app_user.dart';
import '../../models/bot.dart';
import '../../providers/app_ui_style_provider.dart';
import '../../providers/repository_providers.dart';
import '../../utils/auto_dismiss_banner.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/dialog_keyboard_shortcuts.dart';
import '../../widgets/glass/glass_dialog.dart';

/// AIエージェント連携（bot API、2026-11-09）の管理ダイアログ（設定>セキュリティ）。
/// 自分のAI（Claude Codeなど）が、自分の参加している全ての広場・一対を読み、返信する
/// ためのトークンを作る。会話ごとの追加・承認・相手の同意は無い（2026-11-09に会話ごとの
/// BOTから一本化）。トークンは作成・再発行の直後に**1度だけ**表示する（サーバーには
/// ハッシュしか残らず、再表示できない）。
class AiIntegrationDialog extends ConsumerWidget {
  const AiIntegrationDialog({
    super.key,
    required this.currentUser,
    required this.isGlass,
  });

  final AppUser currentUser;
  final bool isGlass;

  static Future<void> show(BuildContext context, WidgetRef ref, AppUser user) {
    return showAppDialog<void>(
      context: context,
      builder: (_) => AiIntegrationDialog(
        currentUser: user,
        isGlass: ref.read(appUiStyleProvider) == AppUiStyle.glass,
      ),
    );
  }

  Future<void> _showToken(BuildContext context, Strings strings, String token) {
    final curl =
        "curl -H 'Authorization: Bot $token' "
        "'https://asia-northeast1-daidai-rhing.cloudfunctions.net/botApi/v1/conversations'";
    return showAppDialog<void>(
      context: context,
      builder: (dialogContext) => _Dialog(
        isGlass: isGlass,
        title: Text(strings.botCreatedTitle),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                strings.botTokenOnceWarning,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              SelectableText(token, style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.copy, size: 18),
                label: Text(strings.botCopyToken),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: token));
                  if (dialogContext.mounted) {
                    showAutoDismissBanner(
                      dialogContext,
                      message: strings.botCopied,
                    );
                  }
                },
              ),
              const SizedBox(height: 16),
              Text(
                strings.botApiLabel,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              SelectableText(curl, style: const TextStyle(fontSize: 11)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(strings.done),
          ),
        ],
      ),
    );
  }

  Future<void> _create(
    BuildContext context,
    WidgetRef ref,
    Strings strings,
  ) async {
    final name = await showAppDialog<String>(
      context: context,
      builder: (_) => _NameDialog(strings: strings, isGlass: isGlass),
    );
    if (name == null || !context.mounted) return;
    try {
      final created = await ref.read(botRepositoryProvider).createBot(name);
      if (!context.mounted) return;
      await _showToken(context, strings, created.token);
    } catch (_) {
      if (context.mounted) {
        showAutoDismissBanner(context, message: strings.botFailed);
      }
    }
  }

  Future<void> _rotate(
    BuildContext context,
    WidgetRef ref,
    Strings strings,
    Bot bot,
  ) async {
    try {
      final token = await ref
          .read(botRepositoryProvider)
          .rotateToken(bot.botId);
      if (!context.mounted) return;
      await _showToken(context, strings, token);
    } catch (_) {
      if (context.mounted) {
        showAutoDismissBanner(context, message: strings.botFailed);
      }
    }
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    Strings strings,
    Bot bot,
  ) async {
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (dialogContext) => _Dialog(
        isGlass: isGlass,
        title: Text(strings.botDeleteTitle),
        content: Text(strings.botDeleteBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(strings.cancel),
          ),
          // 後戻りしにくい確定ボタンは鮮やかな赤（CLAUDE.mdのボタン配色の規約）。
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(strings.botDelete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(botRepositoryProvider).deleteBot(bot.botId);
    } catch (_) {
      if (context.mounted) {
        showAutoDismissBanner(context, message: strings.botFailed);
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    return _Dialog(
      isGlass: isGlass,
      title: Text(strings.assistantTitle),
      content: SizedBox(
        width: 360,
        child: StreamBuilder<List<Bot>>(
          stream: ref
              .read(botRepositoryProvider)
              .watchMyBots(currentUser.userId),
          builder: (context, snapshot) {
            final bots = snapshot.data ?? const <Bot>[];
            return ListView(
              shrinkWrap: true,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    strings.assistantDescription,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                for (final bot in bots)
                  ListTile(
                    leading: const Icon(Icons.smart_toy_outlined),
                    title: Text(bot.name),
                    trailing: Wrap(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.vpn_key_outlined),
                          tooltip: strings.botRotate,
                          onPressed: () => _rotate(context, ref, strings, bot),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: strings.botDelete,
                          onPressed: () => _delete(context, ref, strings, bot),
                        ),
                      ],
                    ),
                  ),
                ListTile(
                  leading: const Icon(Icons.add),
                  title: Text(strings.assistantCreate),
                  onTap: () => _create(context, ref, strings),
                ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.done),
        ),
      ],
    );
  }
}

/// ガラス・それ以外で同じ見た目のダイアログを出す為の薄いラッパー。
class _Dialog extends StatelessWidget {
  const _Dialog({
    required this.isGlass,
    required this.title,
    required this.content,
    required this.actions,
  });

  final bool isGlass;
  final Widget title;
  final Widget content;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return isGlass
        ? GlassAlertDialog(title: title, content: content, actions: actions)
        : KeyboardAlertDialog(title: title, content: content, actions: actions);
  }
}

/// 名前の入力。コントローラはこの`State`が持つ（ダイアログが閉じた後に破棄）。
class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.strings, required this.isGlass});

  final Strings strings;
  final bool isGlass;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    return _Dialog(
      isGlass: widget.isGlass,
      title: Text(strings.assistantCreate),
      content: TextField(
        controller: _controller,
        maxLength: 40,
        autofocus: true,
        decoration: InputDecoration(labelText: strings.botNameLabel),
        onChanged: (_) => setState(() {}),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.cancel),
        ),
        FilledButton(
          onPressed: _controller.text.trim().isEmpty
              ? null
              : () => Navigator.of(context).pop(_controller.text.trim()),
          child: Text(strings.botCreate),
        ),
      ],
    );
  }
}
