import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';
import '../../utils/attachment_upload.dart';
import 'attachment_popup_button.dart';
import '../../models/app_ui_style.dart';
import '../../models/message.dart';
import '../../models/scheduled_message.dart';
import '../../providers/app_ui_style_provider.dart';
import '../../providers/repository_providers.dart';
import '../../utils/auto_dismiss_banner.dart';
import '../../widgets/app_dialog.dart';
import '../calendar/date_time_pick.dart';
import '../../theme/block/block_theme.dart';
import '../../theme/gekiga/gekiga_colors.dart';
import '../../theme/popup_surface_colors.dart';
import '../../widgets/gekiga/gekiga_rect_box.dart';
import '../../widgets/glass/glass_dialog.dart';
import '../../widgets/media_viewer_screen.dart';

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
          // 1件ずつ区切り線で分け、上に添付（画像・ファイル・ぺったん）、下に文字を出す。
          return ListView.separated(
            shrinkWrap: true,
            itemCount: items.length,
            separatorBuilder: (_, _) => Divider(
              height: 1,
              thickness: 1.5,
              // 薄くて見えにくかったので、文字色に近い濃さにする。
              color: switch (uiStyle) {
                AppUiStyle.gekiga => GekigaColors.onPanel,
                AppUiStyle.block => BlockTheme.lineColor(
                  Theme.of(context).brightness,
                ),
                _ => Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.55),
              },
            ),
            itemBuilder: (context, index) {
              final item = items[index];
              final files = item.files;
              final sticker = item.stickerUrl;
              final text = item.bodyText;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (files.isNotEmpty || sticker != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            if (sticker != null)
                              _ScheduledThumb.sticker(sticker)
                            else
                              for (final file in files)
                                _ScheduledThumb.file(file, siblings: files),
                          ],
                        ),
                      ),
                    if (text.isNotEmpty)
                      Text(text, maxLines: 4, overflow: TextOverflow.ellipsis),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.isFailed
                                ? _failText(strings, item.failReason)
                                : formatScheduledTime(item.sendAt),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        if (item.isPending)
                          IconButton(
                            tooltip: strings.scheduledEditAction,
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () =>
                                showEditScheduledDialog(context, item),
                          ),
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
                  ],
                ),
              );
            },
          );
        },
      ),
    );
    return _styledDialog(
      context: context,
      uiStyle: uiStyle,
      title: Text(strings.scheduledListTitle),
      content: content,
    );
  }
}

/// UIスタイルに沿ったダイアログの外枠（劇画はギザギザの太線の箱・文字は白、ガラスはガラス、
/// それ以外は標準の`AlertDialog`）。送信予約の一覧と編集で共通。
Widget _styledDialog({
  required BuildContext context,
  required AppUiStyle uiStyle,
  required Widget title,
  required Widget content,
  List<Widget>? actions,
}) {
  if (uiStyle == AppUiStyle.gekiga) {
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
                if (actions != null) ...[
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: actions,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
  return uiStyle == AppUiStyle.glass
      ? GlassAlertDialog(title: title, content: content, actions: actions)
      : AlertDialog(title: title, content: content, actions: actions);
}

/// 送信予約の編集ダイアログ（文字と添付を直す）。保存したらtrue。
Future<bool?> showEditScheduledDialog(
  BuildContext context,
  ScheduledMessage item,
) {
  return showAppDialog<bool>(
    context: context,
    builder: (_) => _EditScheduledDialog(item: item),
  );
}

class _EditScheduledDialog extends ConsumerStatefulWidget {
  const _EditScheduledDialog({required this.item});

  final ScheduledMessage item;

  @override
  ConsumerState<_EditScheduledDialog> createState() =>
      _EditScheduledDialogState();
}

class _EditScheduledDialogState extends ConsumerState<_EditScheduledDialog> {
  late final TextEditingController _text = TextEditingController(
    text: widget.item.bodyText,
  );
  late final List<MessageFileMetadata> _kept = [...widget.item.files];
  final List<PickedAttachment> _added = [];
  double? _progress;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  int get _count => _kept.length + _added.length;

  Future<void> _save() async {
    final strings = ref.read(appStringsProvider);
    if (_text.text.trim().isEmpty && _count == 0) {
      setState(() => _error = strings.scheduledEditEmpty);
      return;
    }
    setState(() {
      _progress = 0;
      _error = null;
    });
    try {
      await ref
          .read(scheduledMessageRepositoryProvider)
          .updateContent(
            widget.item,
            text: _text.text,
            kept: _kept,
            added: [
              for (final a in _added)
                AttachmentUploadInput(
                  bytes: a.bytes,
                  fileName: a.fileName,
                  contentType: a.contentType,
                ),
            ],
            onProgress: (p) {
              if (mounted) setState(() => _progress = p);
            },
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _progress = null;
          _error = strings.scheduledEditFailed;
        });
      }
    }
  }

  void _onPicked(List<PickedAttachment> picked) {
    final strings = ref.read(appStringsProvider);
    final room = kMaxMultiAttachments - _count;
    setState(() {
      _added.addAll(picked.take(room));
      _error = picked.length > room
          ? strings.chatPendingTrayLimitMessage(kMaxMultiAttachments)
          : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final uiStyle = ref.watch(appUiStyleProvider);
    final busy = _progress != null;
    final isSticker = widget.item.contentType == 'sticker';
    final content = SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isSticker && widget.item.stickerUrl != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _ScheduledThumb.sticker(widget.item.stickerUrl!),
              ),
            if (!isSticker) ...[
              if (_count > 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (var i = 0; i < _kept.length; i++)
                        _RemovableThumb(
                          onRemove: busy
                              ? null
                              : () => setState(() => _kept.removeAt(i)),
                          child: _ScheduledThumb.file(
                            _kept[i],
                            siblings: _kept,
                          ),
                        ),
                      for (var i = 0; i < _added.length; i++)
                        _RemovableThumb(
                          onRemove: busy
                              ? null
                              : () => setState(() => _added.removeAt(i)),
                          child: _ScheduledThumb.picked(_added[i]),
                        ),
                    ],
                  ),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: AttachmentPopupButton(
                  strings: strings,
                  isGekiga: uiStyle == AppUiStyle.gekiga,
                  onPicked: _onPicked,
                ),
              ),
            ],
            if (!isSticker)
              TextField(
                controller: _text,
                enabled: !busy,
                minLines: 2,
                maxLines: 8,
                decoration: InputDecoration(
                  hintText: strings.scheduledEditHint,
                ),
              ),
            if (busy)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: LinearProgressIndicator(value: _progress),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),
          ],
        ),
      ),
    );
    return _styledDialog(
      context: context,
      uiStyle: uiStyle,
      title: Text(strings.scheduledEditTitle),
      content: content,
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.of(context).pop(false),
          child: Text(strings.cancel),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: busy || isSticker ? null : _save,
          child: Text(strings.save),
        ),
      ],
    );
  }
}

/// 右上に×を付けたサムネイル（編集ダイアログで添付を外す）。
class _RemovableThumb extends StatelessWidget {
  const _RemovableThumb({required this.child, required this.onRemove});

  final Widget child;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          top: -6,
          right: -6,
          child: GestureDetector(
            onTap: onRemove,
            child: const CircleAvatar(
              radius: 10,
              backgroundColor: Colors.black87,
              child: Icon(Icons.close, size: 12, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}

/// 送信予約の一覧の添付1つ分の小さなサムネイル（画像は画像、動画・ファイルはアイコンと名前）。
class _ScheduledThumb extends StatelessWidget {
  const _ScheduledThumb.file(MessageFileMetadata file, {this.siblings})
    : _url = null,
      _file = file,
      _picked = null;
  const _ScheduledThumb.sticker(String url)
    : siblings = null,
      _url = url,
      _file = null,
      _picked = null;
  const _ScheduledThumb.picked(PickedAttachment picked)
    : siblings = null,
      _url = null,
      _file = null,
      _picked = picked;

  final String? _url;
  final MessageFileMetadata? _file;
  final PickedAttachment? _picked;

  /// 同じメッセージの添付一覧。タップで拡大する時に、画像・動画だけを順にめくれる。
  final List<MessageFileMetadata>? siblings;

  static const double _size = 56;

  void _open(BuildContext context, MessageFileMetadata file) {
    final media = [
      for (final f in siblings ?? [file])
        if (f.isImage || f.isVideo) f,
    ];
    openMediaViewer(
      context,
      items: [
        for (var i = 0; i < media.length; i++)
          MediaViewerItem(
            id: 'scheduled-$i',
            url: media[i].url,
            contentType: media[i].isVideo ? 'video' : 'image',
            fileName: media[i].fileName,
            thumbnailUrl: media[i].thumbnailUrl,
            playbackUrl: media[i].playbackUrl,
          ),
      ],
      initialIndex: media.indexOf(file).clamp(0, media.length - 1),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final file = _file;
    final picked = _picked;
    final Widget child;
    if (picked != null) {
      child = switch (picked.contentType) {
        'image' => Image.memory(
          picked.bytes,
          fit: BoxFit.cover,
          cacheWidth: (_size * 2).round(),
          errorBuilder: (_, _, _) => const Icon(Icons.image_outlined),
        ),
        'video' => const Icon(Icons.play_circle_outline),
        _ => Padding(
          padding: const EdgeInsets.all(4),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.insert_drive_file_outlined, size: 20),
              Text(
                picked.fileName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ),
        ),
      };
    } else if (_url != null) {
      child = Image.network(
        _url,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => const Icon(Icons.emoji_emotions_outlined),
      );
    } else if (file!.isImage) {
      child = Image.network(
        file.url,
        fit: BoxFit.cover,
        cacheWidth: (_size * 2).round(),
        errorBuilder: (_, _, _) => const Icon(Icons.image_outlined),
      );
    } else if (file.isVideo) {
      child = const Icon(Icons.play_circle_outline);
    } else {
      child = Padding(
        padding: const EdgeInsets.all(4),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.insert_drive_file_outlined, size: 20),
            Text(
              file.fileName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
      );
    }
    final box = Container(
      width: _size,
      height: _size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      alignment: Alignment.center,
      child: child,
    );
    if (file != null && (file.isImage || file.isVideo)) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _open(context, file),
        child: box,
      );
    }
    return box;
  }
}
