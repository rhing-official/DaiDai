import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../l10n/strings.dart';
import '../../models/app_ui_style.dart';
import '../../models/app_user.dart';
import '../../models/group.dart';
import '../../models/webhook.dart';
import '../../providers/app_ui_style_provider.dart';
import '../../providers/repository_providers.dart';
import '../../utils/auto_dismiss_banner.dart';
import '../../widgets/glass/glass_dialog.dart';

/// 受信Webhook（寄合へ外部から投稿できる、bot・API段階1、2026-10-10追加）の
/// 管理画面（広場の設定からのポップアップの中身）。`manageBots`権限を持つ
/// メンバーだけが開ける（呼び出し側で項目自体を出し分ける）。一覧・作成・削除。
/// 作成直後に**URLを1回だけ**表示してコピーさせる（URLにトークンを含むため、
/// サーバーにはハッシュしか残らず再表示できない）。
class WebhookManagementPopup extends ConsumerWidget {
  const WebhookManagementPopup({
    required this.currentUser,
    required this.group,
    super.key,
  });

  final AppUser currentUser;
  final Group group;

  Future<void> _showDialog(
    BuildContext context,
    WidgetRef ref, {
    required Widget title,
    required Widget content,
    required List<Widget> actions,
  }) {
    final isGlass = ref.read(appUiStyleProvider) == AppUiStyle.glass;
    return showDialog<void>(
      context: context,
      builder: (_) => isGlass
          ? GlassAlertDialog(title: title, content: content, actions: actions)
          : AlertDialog(title: title, content: content, actions: actions),
    );
  }

  Future<void> _create(
    BuildContext context,
    WidgetRef ref,
    Strings strings,
  ) async {
    final rooms = await ref
        .read(groupRepositoryProvider)
        .watchRooms(groupId: group.groupId, userId: currentUser.userId)
        .first;
    if (!context.mounted || rooms.isEmpty) return;
    final result = await showDialog<({String name, String roomId})>(
      context: context,
      builder: (_) => _CreateWebhookDialog(
        strings: strings,
        rooms: [for (final room in rooms) (id: room.roomId, name: room.name)],
        isGlass: ref.read(appUiStyleProvider) == AppUiStyle.glass,
      ),
    );
    if (result == null || !context.mounted) return;
    final name = result.name;
    final roomId = result.roomId;

    try {
      final created = await ref
          .read(webhookRepositoryProvider)
          .createWebhook(groupId: group.groupId, roomId: roomId, name: name);
      if (!context.mounted) return;
      await _showCreated(context, ref, strings, created);
    } catch (_) {
      if (context.mounted) {
        showAutoDismissBanner(context, message: strings.webhookCreateFailed);
      }
    }
  }

  /// 作成直後にURLを1回だけ表示する。
  Future<void> _showCreated(
    BuildContext context,
    WidgetRef ref,
    Strings strings,
    CreatedWebhook created,
  ) {
    final curl =
        "curl -X POST -H 'Content-Type: application/json' "
        "-d '{\"content\":\"Hello\"}' '${created.url}'";
    return _showDialog(
      context,
      ref,
      title: Text(strings.webhookCreatedTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              strings.webhookUrlOnceWarning,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            SelectableText(created.url, style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.copy, size: 18),
              label: Text(strings.webhookCopyUrl),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: created.url));
                if (context.mounted) {
                  showAutoDismissBanner(
                    context,
                    message: strings.webhookCopied,
                  );
                }
              },
            ),
            const SizedBox(height: 16),
            Text(
              strings.webhookCurlLabel,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            SelectableText(curl, style: const TextStyle(fontSize: 11)),
          ],
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

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    Strings strings,
    Webhook webhook,
  ) async {
    final isGlass = ref.read(appUiStyleProvider) == AppUiStyle.glass;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final title = Text(strings.webhookDeleteTitle);
        final content = Text(strings.webhookDeleteBody);
        final actions = [
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
            child: Text(strings.webhookDeleteConfirm),
          ),
        ];
        return isGlass
            ? GlassAlertDialog(title: title, content: content, actions: actions)
            : AlertDialog(title: title, content: content, actions: actions);
      },
    );
    if (confirmed != true) return;
    await ref
        .read(webhookRepositoryProvider)
        .deleteWebhook(groupId: group.groupId, webhookId: webhook.webhookId);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final format = DateFormat('yyyy/MM/dd HH:mm');
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
                  strings.webhookTitle,
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
            strings.webhookDescription,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const Divider(height: 1),
        Flexible(
          child: StreamBuilder<List<Webhook>>(
            stream: ref
                .read(webhookRepositoryProvider)
                .watchWebhooks(group.groupId),
            builder: (context, snapshot) {
              final webhooks = snapshot.data ?? const <Webhook>[];
              return StreamBuilder(
                stream: ref
                    .read(groupRepositoryProvider)
                    .watchRooms(
                      groupId: group.groupId,
                      userId: currentUser.userId,
                    ),
                builder: (context, roomsSnapshot) {
                  final roomNames = {
                    for (final room in roomsSnapshot.data ?? const [])
                      room.roomId: room.name,
                  };
                  return ListView(
                    shrinkWrap: true,
                    children: [
                      if (webhooks.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(24),
                          child: Center(child: Text(strings.webhookEmpty)),
                        ),
                      for (final webhook in webhooks)
                        ListTile(
                          leading: const Icon(Icons.webhook_outlined),
                          title: Text(webhook.name),
                          subtitle: Text(
                            '${roomNames[webhook.roomId] ?? ''}'
                            ' ・ '
                            '${webhook.lastUsedAt == null ? strings.webhookNeverUsed : strings.webhookLastUsed(format.format(webhook.lastUsedAt!.toDate()))}',
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline),
                            tooltip: '',
                            onPressed: () =>
                                _delete(context, ref, strings, webhook),
                          ),
                        ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.add),
                        title: Text(strings.webhookCreateButton),
                        onTap: () => _create(context, ref, strings),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

/// 作成ダイアログ（名前と投稿先の寄合）。入力欄のコントローラはこの`State`が
/// 持ち、ダイアログが完全に閉じた後に破棄する（閉じるアニメーション中に
/// 破棄済みのコントローラを使わないため）。
class _CreateWebhookDialog extends StatefulWidget {
  const _CreateWebhookDialog({
    required this.strings,
    required this.rooms,
    required this.isGlass,
  });

  final Strings strings;
  final List<({String id, String name})> rooms;
  final bool isGlass;

  @override
  State<_CreateWebhookDialog> createState() => _CreateWebhookDialogState();
}

class _CreateWebhookDialogState extends State<_CreateWebhookDialog> {
  final _nameController = TextEditingController();
  late String _roomId = widget.rooms.first.id;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    final title = Text(strings.webhookCreateButton);
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _nameController,
          maxLength: 40,
          autofocus: true,
          decoration: InputDecoration(labelText: strings.webhookNameLabel),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: _roomId,
          decoration: InputDecoration(labelText: strings.webhookRoomLabel),
          items: [
            for (final room in widget.rooms)
              DropdownMenuItem(value: room.id, child: Text(room.name)),
          ],
          onChanged: (value) {
            if (value != null) setState(() => _roomId = value);
          },
        ),
      ],
    );
    final actions = [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(strings.cancel),
      ),
      FilledButton(
        onPressed: _nameController.text.trim().isEmpty
            ? null
            : () => Navigator.of(
                context,
              ).pop((name: _nameController.text.trim(), roomId: _roomId)),
        child: Text(strings.webhookCreateConfirm),
      ),
    ];
    return widget.isGlass
        ? GlassAlertDialog(title: title, content: content, actions: actions)
        : AlertDialog(title: title, content: content, actions: actions);
  }
}
