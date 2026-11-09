import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';
import '../../models/app_ui_style.dart';
import '../../models/app_user.dart';
import '../../models/bot.dart';
import '../../models/direct_message.dart';
import '../../models/group.dart';
import '../../models/group_role.dart';
import '../../providers/app_ui_style_provider.dart';
import '../../providers/repository_providers.dart';
import '../../utils/auto_dismiss_banner.dart';
import '../../utils/group_permissions.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/dialog_keyboard_shortcuts.dart';
import '../../widgets/glass/glass_dialog.dart';

/// bot API（AIが寄合のメッセージを読み、返信できる、2026-11-09、段階2a）の
/// 広場側の画面（広場の設定からのポップアップの中身）。メンバーなら誰でも
/// 「どのBOTが読めるか」を確認でき、自分のBOTを追加できる（長・`manageBots`
/// 権限者の追加は即有効、それ以外は承認待ち）。承認・却下・外す操作は
/// 長・`manageBots`権限者のみ（BOTの所有者は自分のBOTを外せる）。
class BotManagementPopup extends ConsumerWidget {
  const BotManagementPopup({
    required this.currentUser,
    this.group,
    this.dm,
    super.key,
  }) : assert((group == null) != (dm == null));

  final AppUser currentUser;

  /// 広場の場合。一対の場合は[dm]（どちらか一方だけ渡す）。
  final Group? group;
  final DirectMessage? dm;

  BotConversation get _conversation => dm != null
      ? BotConversation.dm(dm!.dmId)
      : BotConversation.group(group!.groupId);

  /// 承認待ちのBOTを承認・却下できるか。広場は`manageBots`権限者、一対は
  /// BOTの所有者**以外**の参加者（相手の同意）。
  bool _canDecide(GroupBot bot) => dm != null
      ? bot.ownerUserId != currentUser.userId
      : hasGroupPermission(
          group: group!,
          userId: currentUser.userId,
          permission: GroupPermission.manageBots,
        );

  /// 有効なBOTを外せるか。広場は`manageBots`権限者かBOTの所有者、一対は参加者なら誰でも。
  bool _canRemove(GroupBot bot) =>
      dm != null || _canDecide(bot) || bot.ownerUserId == currentUser.userId;

  Future<void> _guard(
    BuildContext context,
    Strings strings,
    Future<void> Function() action, {
    String? successMessage,
  }) async {
    try {
      await action();
      if (context.mounted && successMessage != null) {
        showAutoDismissBanner(context, message: successMessage);
      }
    } catch (_) {
      if (context.mounted) {
        showAutoDismissBanner(context, message: strings.botFailed);
      }
    }
  }

  Future<void> _addMine(
    BuildContext context,
    WidgetRef ref,
    Strings strings,
    List<GroupBot> inGroup,
  ) async {
    final mine = await ref
        .read(botRepositoryProvider)
        .watchMyBots(currentUser.userId)
        .first;
    if (!context.mounted) return;
    final present = {for (final b in inGroup) b.botId};
    final candidates = [
      for (final bot in mine)
        if (!present.contains(bot.botId)) bot,
    ];
    if (candidates.isEmpty) {
      showAutoDismissBanner(context, message: strings.botNoneToAdd);
      return;
    }
    final picked = await showAppDialog<Bot>(
      context: context,
      builder: (dialogContext) => _BotDialog(
        isGlass: ref.read(appUiStyleProvider) == AppUiStyle.glass,
        title: Text(strings.botAddMine),
        content: SizedBox(
          width: 320,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final bot in candidates)
                ListTile(
                  leading: const Icon(Icons.smart_toy_outlined),
                  title: Text(bot.name),
                  onTap: () => Navigator.of(dialogContext).pop(bot),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(strings.cancel),
          ),
        ],
      ),
    );
    if (picked == null || !context.mounted) return;
    try {
      final status = await ref
          .read(botRepositoryProvider)
          .requestAddition(conversation: _conversation, botId: picked.botId);
      if (context.mounted) {
        showAutoDismissBanner(
          context,
          message: status == GroupBotStatus.active
              ? strings.botAdded
              : (dm != null ? strings.botRequestedDm : strings.botRequested),
        );
      }
    } catch (_) {
      if (context.mounted) {
        showAutoDismissBanner(context, message: strings.botFailed);
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final repository = ref.read(botRepositoryProvider);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 4, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  strings.botTitle,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            '${dm != null ? strings.botDescriptionDm : strings.botDescription}\n${strings.botReadScope}',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const Divider(height: 1),
        Flexible(
          child: StreamBuilder<List<GroupBot>>(
            stream: repository.watchConversationBots(_conversation),
            builder: (context, snapshot) {
              final bots = snapshot.data ?? const <GroupBot>[];
              return ListView(
                shrinkWrap: true,
                children: [
                  if (bots.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(child: Text(strings.botEmpty)),
                    ),
                  for (final bot in bots)
                    ListTile(
                      leading: const Icon(Icons.smart_toy_outlined),
                      title: Text(bot.name),
                      subtitle: bot.status == GroupBotStatus.pending
                          ? Text(
                              dm != null
                                  ? strings.botPendingDm
                                  : strings.botPendingBadge,
                            )
                          : null,
                      trailing: Wrap(
                        children: [
                          if (bot.status == GroupBotStatus.pending &&
                              _canDecide(bot)) ...[
                            TextButton(
                              onPressed: () => _guard(
                                context,
                                strings,
                                () => repository.respond(
                                  conversation: _conversation,
                                  botId: bot.botId,
                                  approve: true,
                                ),
                              ),
                              child: Text(strings.botApprove),
                            ),
                            TextButton(
                              onPressed: () => _guard(
                                context,
                                strings,
                                () => repository.respond(
                                  conversation: _conversation,
                                  botId: bot.botId,
                                  approve: false,
                                ),
                              ),
                              child: Text(strings.botReject),
                            ),
                          ] else if (_canRemove(bot))
                            TextButton(
                              onPressed: () => _guard(
                                context,
                                strings,
                                () => repository.remove(
                                  conversation: _conversation,
                                  botId: bot.botId,
                                ),
                              ),
                              child: Text(strings.botRemove),
                            ),
                        ],
                      ),
                    ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.add),
                    title: Text(strings.botAddMine),
                    onTap: () => _addMine(context, ref, strings, bots),
                  ),
                  ListTile(
                    leading: const Icon(Icons.manage_accounts_outlined),
                    title: Text(strings.botManageMine),
                    onTap: () => showAppDialog<void>(
                      context: context,
                      builder: (_) => _MyBotsDialog(
                        currentUser: currentUser,
                        isGlass:
                            ref.read(appUiStyleProvider) == AppUiStyle.glass,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

/// ガラス・それ以外で同じ見た目のダイアログを出す為の薄いラッパー。
class _BotDialog extends StatelessWidget {
  const _BotDialog({
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

/// 自分のBOTの管理（作成・トークン再発行・削除）。
class _MyBotsDialog extends ConsumerWidget {
  const _MyBotsDialog({required this.currentUser, required this.isGlass});

  final AppUser currentUser;
  final bool isGlass;

  Future<void> _showToken(
    BuildContext context,
    Strings strings,
    String botId,
    String token,
  ) {
    final curl =
        "curl -H 'Authorization: Bot $token' "
        "'https://asia-northeast1-daidai-rhing.cloudfunctions.net/botApi/v1/conversations'";
    return showAppDialog<void>(
      context: context,
      builder: (dialogContext) => _BotDialog(
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
      await _showToken(context, strings, created.botId, created.token);
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
      await _showToken(context, strings, bot.botId, token);
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
      builder: (dialogContext) => _BotDialog(
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
    return _BotDialog(
      isGlass: isGlass,
      title: Text(strings.botMineTitle),
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
                  title: Text(strings.botCreate),
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

/// BOTの名前の入力。コントローラはこの`State`が持つ（ダイアログが閉じた後に破棄）。
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
    return _BotDialog(
      isGlass: widget.isGlass,
      title: Text(strings.botCreate),
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
