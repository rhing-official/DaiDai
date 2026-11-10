import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';
import '../../models/app_ui_style.dart';
import '../../models/scheduled_message.dart';
import '../../providers/app_ui_style_provider.dart';
import '../../providers/repository_providers.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/glass/glass_dialog.dart';

/// その寄合の、自分の送信予定（一覧・件数の表示に使う）。
final scheduledMessagesProvider = StreamProvider.autoDispose
    .family<
      List<ScheduledMessage>,
      ({String userId, String conversationId, String roomId})
    >((ref, key) {
      return ref
          .watch(scheduledMessageRepositoryProvider)
          .watch(
            userId: key.userId,
            conversationId: key.conversationId,
            roomId: key.roomId,
          );
    });

/// 送信ボタンの長押しメニューの選択肢（2026-11-10）。
enum SendOptionChoice { silent, schedule }

/// 送信予定の日時の表示（今年は「月/日 時:分」、他の年は年も付ける）。
String formatScheduledTime(DateTime time, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final hm =
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  final md = '${time.month}/${time.day}';
  return time.year == n.year ? '$md $hm' : '${time.year}/$md $hm';
}

/// 送信ボタンの長押しメニュー（通知なしで送信／日時を指定して送信）。
Future<SendOptionChoice?> showSendOptionsMenu({
  required BuildContext context,
  required Strings strings,
  required Offset globalPosition,
}) {
  final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
  return showMenu<SendOptionChoice>(
    context: context,
    position: RelativeRect.fromRect(
      Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 0, 0),
      Offset.zero & overlay.size,
    ),
    items: [
      PopupMenuItem(
        value: SendOptionChoice.silent,
        child: Row(
          children: [
            const Icon(Icons.notifications_off_outlined, size: 20),
            const SizedBox(width: 12),
            Text(strings.scheduledSendOptionSilent),
          ],
        ),
      ),
      PopupMenuItem(
        value: SendOptionChoice.schedule,
        child: Row(
          children: [
            const Icon(Icons.schedule_send_outlined, size: 20),
            const SizedBox(width: 12),
            Text(strings.scheduledSendOptionSchedule),
          ],
        ),
      ),
    ],
  );
}

/// 送信する日時を選ぶ（日付→時刻）。範囲は今から1分後〜[kScheduledMaxDays]日後。
/// 範囲外（1分以内など）を選んだらnullを返さず、案内を出してnull。
Future<DateTime?> pickScheduledDateTime({
  required BuildContext context,
  required Strings strings,
  DateTime? initial,
}) async {
  final now = DateTime.now();
  final first = DateTime(now.year, now.month, now.day);
  final last = now.add(const Duration(days: kScheduledMaxDays));
  final start = initial != null && initial.isAfter(now)
      ? initial
      : now.add(const Duration(hours: 1));
  final date = await showDatePicker(
    context: context,
    initialDate: start,
    firstDate: first,
    lastDate: last,
    helpText: strings.scheduledPickerHelp,
  );
  if (date == null || !context.mounted) return null;
  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(start),
    helpText: strings.scheduledPickerHelp,
  );
  if (time == null) return null;
  final picked = DateTime(
    date.year,
    date.month,
    date.day,
    time.hour,
    time.minute,
  );
  final ok =
      picked.isAfter(DateTime.now().add(const Duration(minutes: 1))) &&
      isScheduledTimeAllowed(picked, DateTime.now());
  if (!ok) {
    if (context.mounted) {
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(strings.scheduledTimeTooSoon)));
    }
    return null;
  }
  return picked;
}

/// 入力欄の上に出す「◯月◯日 HH:mm に送信 ×」のチップ。次の1回の送信が予定になる。
class ScheduledSendChip extends StatelessWidget {
  const ScheduledSendChip({
    required this.sendAt,
    required this.strings,
    required this.onClear,
    super.key,
  });

  final DateTime sendAt;
  final Strings strings;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
        child: InputChip(
          avatar: Icon(Icons.schedule_send_outlined, color: scheme.onSurface),
          label: Text(strings.scheduledChipLabel(formatScheduledTime(sendAt))),
          onDeleted: onClear,
          deleteIconColor: scheme.onSurface,
        ),
      ),
    );
  }
}

/// その寄合の送信予定の一覧（確認・日時の変更・取り消し）。
Future<void> showScheduledMessagesDialog({
  required BuildContext context,
  required String userId,
  required String conversationId,
  required String roomId,
}) {
  return showAppDialog<void>(
    context: context,
    builder: (_) => _ScheduledMessagesDialog(
      userId: userId,
      conversationId: conversationId,
      roomId: roomId,
    ),
  );
}

class _ScheduledMessagesDialog extends ConsumerWidget {
  const _ScheduledMessagesDialog({
    required this.userId,
    required this.conversationId,
    required this.roomId,
  });

  final String userId;
  final String conversationId;
  final String roomId;

  String _failText(Strings s, String? reason) => switch (reason) {
    'notMember' => s.scheduledFailedNotMember,
    'conversationMissing' => s.scheduledFailedMissing,
    _ => s.scheduledFailedInvalid,
  };

  IconData _icon(String type) => switch (type) {
    'image' => Icons.image_outlined,
    'video' => Icons.videocam_outlined,
    'file' => Icons.attach_file,
    'multi' => Icons.collections_outlined,
    'sticker' => Icons.emoji_emotions_outlined,
    _ => Icons.chat_bubble_outline,
  };

  Future<void> _cancel(
    BuildContext context,
    WidgetRef ref,
    Strings strings,
    ScheduledMessage item,
  ) async {
    final ok = await showAppDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(strings.scheduledCancelConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(strings.scheduledCancelAction),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(scheduledMessageRepositoryProvider).cancel(item);
  }

  Future<void> _reschedule(
    BuildContext context,
    WidgetRef ref,
    Strings strings,
    ScheduledMessage item,
  ) async {
    final picked = await pickScheduledDateTime(
      context: context,
      strings: strings,
      initial: item.sendAt,
    );
    if (picked == null) return;
    await ref
        .read(scheduledMessageRepositoryProvider)
        .reschedule(item.id, picked);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final isGlass = ref.watch(appUiStyleProvider) == AppUiStyle.glass;
    final snapshot = ref.watch(
      scheduledMessagesProvider((
        userId: userId,
        conversationId: conversationId,
        roomId: roomId,
      )),
    );
    final content = SizedBox(
      width: 420,
      child: Builder(
        builder: (context) {
          final items = snapshot.value ?? const <ScheduledMessage>[];
          if (items.isEmpty) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                strings.scheduledListEmpty,
                textAlign: TextAlign.center,
              ),
            );
          }
          return ListView(
            shrinkWrap: true,
            children: [
              for (final item in items)
                ListTile(
                  leading: Icon(_icon(item.contentType)),
                  title: Text(
                    item.content.isEmpty
                        ? strings.scheduledAttachmentKind
                        : item.content,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    item.isFailed
                        ? _failText(strings, item.failReason)
                        : formatScheduledTime(item.sendAt),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (item.isPending)
                        IconButton(
                          tooltip: strings.scheduledRescheduleAction,
                          icon: const Icon(Icons.edit_calendar_outlined),
                          onPressed: () =>
                              _reschedule(context, ref, strings, item),
                        ),
                      IconButton(
                        tooltip: strings.scheduledCancelAction,
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _cancel(context, ref, strings, item),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
    final title = Text(strings.scheduledListTitle);
    return isGlass
        ? GlassAlertDialog(title: title, content: content)
        : AlertDialog(title: title, content: content);
  }
}
