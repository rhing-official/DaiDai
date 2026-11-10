import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';
import '../../models/app_ui_style.dart';
import '../../models/scheduled_message.dart';
import '../../providers/app_ui_style_provider.dart';
import '../../providers/repository_providers.dart';
import '../../utils/auto_dismiss_banner.dart';
import '../../widgets/app_dialog.dart';
import '../calendar/date_time_pick.dart';
import '../../theme/gekiga/gekiga_colors.dart';
import '../../theme/popup_surface_colors.dart';
import '../../widgets/gekiga/gekiga_rect_box.dart';
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

/// ポップアップ・メニューの外枠（UIスタイルに沿った意匠、2026-11-10）。劇画はギザギザの太線の箱、
/// それ以外は他のポップアップと共通の`popupCardDecoration`（版画は太枠と硬い影、
/// フラット・ガラスは中立グレーの面と細い枠）。
class StyledPopupCard extends StatelessWidget {
  const StyledPopupCard({
    required this.uiStyle,
    required this.child,
    super.key,
  });

  final AppUiStyle uiStyle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (uiStyle == AppUiStyle.gekiga) {
      return GekigaRectBox(
        child: Padding(padding: const EdgeInsets.all(10), child: child),
      );
    }
    final brightness = Theme.of(context).brightness;
    return DecoratedBox(
      decoration: popupCardDecoration(context, brightness, uiStyle),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Material(color: Colors.transparent, child: child),
      ),
    );
  }
}

/// 送信ボタン長押しメニューの操作口。長押しを続けたまま指（ポインター）を動かして項目へなぞり、
/// 離すと選べる（＋ボタンのポップアップと同じ）。ほとんど動かさず離した場合は開いたままで、
/// 項目をタップして選ぶ。
class SendOptionsMenuHandle {
  SendOptionsMenuHandle._(this.result, this._update, this._release);

  /// 選ばれた項目（外をタップして閉じたらnull）。
  final Future<SendOptionChoice?> result;
  final void Function(Offset globalPosition) _update;
  final void Function(Offset globalPosition) _release;

  void update(Offset globalPosition) => _update(globalPosition);
  void release(Offset globalPosition) => _release(globalPosition);
}

/// 送信ボタン（飛行機）の長押しメニュー（通知なしで送信／日時を指定して送信）。
/// ボタン（[anchorBox]）の真上に、右端を揃えて出す。`showMenu`は位置の基準が環境によってずれる
/// ため、＋ボタンのポップアップと同じく、オーバーレイへ直接置く（2026-11-10）。
SendOptionsMenuHandle showSendOptionsMenu({
  required BuildContext context,
  required Strings strings,
  required RenderBox anchorBox,
}) {
  final overlayState = Overlay.of(context);
  final overlayBox = overlayState.context.findRenderObject()! as RenderBox;
  final anchor =
      anchorBox.localToGlobal(Offset.zero, ancestor: overlayBox) &
      anchorBox.size;
  final uiStyle = ProviderScope.containerOf(context).read(appUiStyleProvider);
  final brightness = Theme.of(context).brightness;
  final fg = popupCardForeground(brightness, uiStyle);
  final highlightColor = uiStyle == AppUiStyle.gekiga
      ? GekigaColors.onPanel.withValues(alpha: 0.2)
      : Theme.of(context).colorScheme.primary.withValues(alpha: 0.15);
  final textStyle = Theme.of(context).textTheme.bodyLarge;
  const width = 250.0;
  const rowHeight = 48.0;
  const gap = 8.0;
  // 劇画の枠の内側の余白（上下10ずつ）を含めた高さ。
  final inset = uiStyle == AppUiStyle.gekiga ? 10.0 : 0.0;
  final menuHeight = rowHeight * 2 + inset * 2;
  final left = (anchor.right - width).clamp(
    8.0,
    (overlayBox.size.width - width - 8).clamp(8.0, double.infinity),
  );
  final top = (anchor.top - menuHeight - gap).clamp(8.0, double.infinity);
  final choices = [SendOptionChoice.silent, SendOptionChoice.schedule];
  final highlighted = ValueNotifier<int>(-1);
  final completer = Completer<SendOptionChoice?>();
  late final OverlayEntry entry;

  void close([SendOptionChoice? value]) {
    if (completer.isCompleted) return;
    entry.remove();
    highlighted.dispose();
    completer.complete(value);
  }

  // ポインター（画面座標）の下の項目。メニューの外ならnull。
  int? indexAt(Offset global) {
    final p = overlayBox.globalToLocal(global);
    final rect = Rect.fromLTWH(left, top + inset, width, rowHeight * 2);
    if (!rect.contains(p)) return null;
    return ((p.dy - rect.top) ~/ rowHeight).clamp(0, 1);
  }

  Widget row(int i, IconData icon, String label) {
    return InkWell(
      onTap: () => close(choices[i]),
      child: ValueListenableBuilder<int>(
        valueListenable: highlighted,
        builder: (_, value, _) => Container(
          height: rowHeight,
          color: value == i ? highlightColor : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Icon(icon, size: 20, color: fg),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textStyle?.copyWith(color: fg),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  entry = OverlayEntry(
    builder: (_) => Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: close,
            child: const ColoredBox(color: Colors.transparent),
          ),
        ),
        Positioned(
          left: left,
          top: top,
          width: width,
          height: menuHeight,
          // オーバーレイには`Material`が無く、`InkWell`が使えないため透明な`Material`を挟む。
          child: Material(
            type: MaterialType.transparency,
            child: StyledPopupCard(
              uiStyle: uiStyle,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  row(
                    0,
                    Icons.notifications_off_outlined,
                    strings.scheduledSendOptionSilent,
                  ),
                  row(
                    1,
                    Icons.schedule_send_outlined,
                    strings.scheduledSendOptionSchedule,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
  overlayState.insert(entry);
  return SendOptionsMenuHandle._(
    completer.future,
    (global) {
      if (completer.isCompleted) return;
      highlighted.value = indexAt(global) ?? -1;
    },
    (global) {
      if (completer.isCompleted) return;
      final i = indexAt(global);
      if (i != null && highlighted.value == i) {
        close(choices[i]);
      } else {
        highlighted.value = -1;
      }
    },
  );
}

/// 送信する日時を選ぶ（日付→時刻）。範囲は今から1分後〜[kScheduledMaxDays]日後。
/// 日付は週の始まりをカレンダーの設定に従う自前のカレンダー（過去は選べない、`/`表記）、
/// 時刻は予定の作成（`calendar_event_form_dialog.dart`）と同じ標準の時刻ピッカー。
/// 範囲外（1分以内など）を選んだら案内を出してnull。
Future<DateTime?> pickScheduledDateTime({
  required BuildContext context,
  required Strings strings,
  required String conversationId,
  DateTime? initial,
}) async {
  final now = DateTime.now();
  final last = now.add(const Duration(days: kScheduledMaxDays));
  final start = initial != null && initial.isAfter(now)
      ? initial
      : now.add(const Duration(hours: 1));
  final picked = await pickDateAndTime(
    context,
    conversationId: conversationId,
    initial: start,
    firstDate: now,
    lastDate: last,
    title: strings.scheduledPickerHelp,
    // 1分以内などは、案内を出して時刻ピッカーを開いたままにする。
    isValid: (picked) =>
        picked.isAfter(DateTime.now().add(const Duration(minutes: 1))) &&
        isScheduledTimeAllowed(picked, DateTime.now()),
    onInvalid: () =>
        showAutoDismissBanner(context, message: strings.scheduledTimeTooSoon),
  );
  if (picked == null) return null;
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
      conversationId: conversationId,
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
    final uiStyle = ref.watch(appUiStyleProvider);
    final isGlass = uiStyle == AppUiStyle.glass;
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
    if (uiStyle == AppUiStyle.gekiga) {
      // 劇画: ギザギザの太線の箱、文字・アイコンは白。
      final base = Theme.of(context);
      final themed = base.copyWith(
        colorScheme: base.colorScheme.copyWith(
          onSurface: GekigaColors.onPanel,
          onSurfaceVariant: GekigaColors.onPanel,
        ),
        textTheme: base.textTheme.apply(
          bodyColor: GekigaColors.onPanel,
          displayColor: GekigaColors.onPanel,
        ),
        listTileTheme: const ListTileThemeData(
          textColor: GekigaColors.onPanel,
          iconColor: GekigaColors.onPanel,
        ),
      );
      return Theme(
        data: themed,
        child: Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          shadowColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(24),
          child: GekigaRectBox(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DefaultTextStyle.merge(
                    style: themed.textTheme.titleLarge,
                    child: title,
                  ),
                  const SizedBox(height: 16),
                  Flexible(child: content),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return isGlass
        ? GlassAlertDialog(title: title, content: content)
        : AlertDialog(title: title, content: content);
  }
}
