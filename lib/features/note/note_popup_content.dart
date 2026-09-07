import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';
import '../../models/app_ui_style.dart';
import '../../models/app_user.dart';
import '../../models/note.dart';
import '../../providers/app_ui_style_provider.dart';
import '../../providers/repository_providers.dart';
import '../../theme/popup_surface_colors.dart';
import '../../utils/auto_dismiss_banner.dart';
import '../../utils/note_title.dart';
import '../../widgets/glass/glass_dialog.dart';
import '../../widgets/glass/glass_surface.dart';

/// ノートボタンの真下にノート一覧をポップアップ表示する（2026-09-06追加、
/// `poll_popup_content.dart`の`showPollPopup`と同じ構成）。位置計算済みの
/// [position]の元で`showMenu`を開き、選ばれた（または新規作成された）
/// [Note]を返す（呼び出し元がそれを使ってペインを全画面ノートエディタへ
/// 切り替える）。ヘッダーの「＋」は投票と異なりフォームダイアログを介さず、
/// [NoteRepository.createNote]で即座に空のノートを作成してそのまま返す
/// （ノートはタイトルと本文だけの単純な構造のため、作成前に入力させる
/// 項目が無い）。
Future<Note?> showNotePopup(
  BuildContext context, {
  required RelativeRect position,
  required bool isDm,
  required String conversationId,
  required String roomId,
  required AppUser currentUser,
}) {
  return showMenu<Note>(
    context: context,
    position: position,
    color: Colors.transparent,
    shadowColor: Colors.transparent,
    elevation: 0,
    items: [
      PopupMenuItem<Note>(
        enabled: false,
        padding: EdgeInsets.zero,
        child: _NotePopupContent(
          isDm: isDm,
          conversationId: conversationId,
          roomId: roomId,
          currentUser: currentUser,
        ),
      ),
    ],
  );
}

class _NotePopupContent extends ConsumerStatefulWidget {
  const _NotePopupContent({
    required this.isDm,
    required this.conversationId,
    required this.roomId,
    required this.currentUser,
  });

  final bool isDm;
  final String conversationId;
  final String roomId;
  final AppUser currentUser;

  @override
  ConsumerState<_NotePopupContent> createState() => _NotePopupContentState();
}

class _NotePopupContentState extends ConsumerState<_NotePopupContent> {
  bool _creating = false;

  Future<void> _createNote() async {
    if (_creating) return;
    setState(() => _creating = true);
    try {
      final strings = ref.read(appStringsProvider);
      final note = await ref
          .read(noteRepositoryProvider)
          .createNote(
            isDm: widget.isDm,
            conversationId: widget.conversationId,
            roomId: widget.roomId,
            createdBy: widget.currentUser.userId,
          );
      // メッセージ画面への通知は副次的な効果であり、失敗してもノートの作成
      // 自体は成功として扱う（poll_form_dialog.dartのsendPollCreatedMessageと
      // 同じ設計判断）。
      try {
        final title = note.title.isEmpty
            ? strings.noteUntitledLabel
            : note.title;
        if (widget.isDm) {
          await ref
              .read(directMessageRepositoryProvider)
              .sendNoteCreatedMessage(
                dmId: widget.conversationId,
                roomId: widget.roomId,
                senderId: widget.currentUser.userId,
                senderRhingId: widget.currentUser.rhingId,
                noteId: note.noteId,
                noteTitle: title,
              );
        } else {
          await ref
              .read(groupRepositoryProvider)
              .sendNoteCreatedMessage(
                groupId: widget.conversationId,
                roomId: widget.roomId,
                senderId: widget.currentUser.userId,
                senderRhingId: widget.currentUser.rhingId,
                noteId: note.noteId,
                noteTitle: title,
              );
        }
      } catch (e) {
        debugPrint('[noteCreatedMessage] failed: $e');
      }
      if (!mounted) return;
      Navigator.of(context).pop(note);
    } catch (e) {
      // 2026-09-06修正: 以前はcatchが無く、ノート作成自体の失敗
      // （firestore.rules未デプロイによるpermission-denied等）が
      // 「＋を押しても読み込みが一瞬出るだけで何も起きない」という
      // 無反応に見えていた（例外がハンドルされずrethrowされ、UIには
      // 何も表示されなかった）。poll_form_dialog.dartと同じくエラー内容を
      // バナーで見えるようにする。
      if (mounted) showAutoDismissBanner(context, message: '$e');
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  /// ノートを削除する（2026-09-07追加）。作成者のみ削除可能
  /// （firestore.rules参照、`build()`側で`onDelete`自体を作成者以外には
  /// 渡さない）。確認ダイアログは`_AlbumPopupContentState._deleteAlbum`
  /// （`album_popup_content.dart`）と同じ型。ノート専用の削除確認本文は
  /// 用意していないため、投票側と同じく`calendarDeleteConfirmMessage`を
  /// 流用する。
  Future<void> _deleteNote(Note note) async {
    final strings = ref.read(appStringsProvider);
    final isGlass = ref.read(appUiStyleProvider) == AppUiStyle.glass;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) {
        final title = Text(strings.noteDeleteConfirmTitle);
        final content = Text(strings.calendarDeleteConfirmMessage);
        final actions = [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            // colorScheme.errorはダークテーマ下でコントラストが不十分に
            // なるため固定の濃い赤にする（CLAUDE.md記載の既存の教訓）。
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
            ),
            child: Text(strings.delete),
          ),
        ];
        return isGlass
            ? GlassAlertDialog(title: title, content: content, actions: actions)
            : AlertDialog(title: title, content: content, actions: actions);
      },
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref
          .read(noteRepositoryProvider)
          .deleteNote(
            isDm: widget.isDm,
            conversationId: widget.conversationId,
            roomId: widget.roomId,
            noteId: note.noteId,
          );
    } catch (e) {
      if (mounted) showAutoDismissBanner(context, message: '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final brightness = Theme.of(context).brightness;
    final uiStyle = ref.watch(appUiStyleProvider);
    final onInverse = popupCardForeground(brightness, uiStyle);

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.note_alt_outlined, size: 16, color: onInverse),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                strings.noteListTitle,
                style: TextStyle(color: onInverse, fontWeight: FontWeight.bold),
              ),
            ),
            _creating
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: onInverse,
                    ),
                  )
                : IconButton(
                    icon: Icon(Icons.add, size: 20, color: onInverse),
                    tooltip: '',
                    onPressed: _createNote,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
          ],
        ),
        const SizedBox(height: 8),
        StreamBuilder<List<Note>>(
          stream: ref
              .read(noteRepositoryProvider)
              .watchNotes(
                isDm: widget.isDm,
                conversationId: widget.conversationId,
                roomId: widget.roomId,
              ),
          builder: (context, snapshot) {
            final notes = snapshot.data ?? const <Note>[];
            if (notes.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  strings.noteListEmptyMessage,
                  style: TextStyle(color: onInverse),
                ),
              );
            }
            final sorted = [...notes]
              ..sort(
                (a, b) => (b.updatedAt?.millisecondsSinceEpoch ?? 0).compareTo(
                  a.updatedAt?.millisecondsSinceEpoch ?? 0,
                ),
              );
            return ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final note in sorted)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _NotePopupCard(
                          note: note,
                          uiStyle: uiStyle,
                          strings: strings,
                          onTap: () => Navigator.of(context).pop(note),
                          onDelete: note.createdBy == widget.currentUser.userId
                              ? () => _deleteNote(note)
                              : null,
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );

    final padded = Padding(padding: const EdgeInsets.all(12), child: content);

    return SizedBox(
      width: 300,
      child: Container(
        decoration: BoxDecoration(
          color: popupCardBackground(brightness, uiStyle),
          border: Border.all(color: popupCardBorder(brightness, uiStyle)),
          borderRadius: BorderRadius.circular(16),
        ),
        child: padded,
      ),
    );
  }
}

/// ポップアップ内のノート1件分のカード。`_PollPopupCard`と同じ見た目の構成。
/// 右上のゴミ箱ボタン（2026-09-07追加、`chat_screen.dart`の
/// `_PinnedMessageCard`が持つ×ボタンと同じ座標・円形サイズのコンセプトを
/// 踏襲。アイコンのみ×→ゴミ箱に変更）は、作成者本人が開いた場合のみ
/// [onDelete]が渡され表示される（他人には`null`、firestore.rulesの
/// 作成者限定削除と一致させるための表示制御）。
class _NotePopupCard extends StatelessWidget {
  const _NotePopupCard({
    required this.note,
    required this.uiStyle,
    required this.strings,
    required this.onTap,
    required this.onDelete,
  });

  final Note note;
  final AppUiStyle uiStyle;
  final Strings strings;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final isGlass = uiStyle == AppUiStyle.glass;
    final brightness = Theme.of(context).brightness;
    final onInverse = popupCardForeground(brightness, uiStyle);
    final title = resolveNoteDisplayTitle(
      note,
      fallback: strings.noteUntitledLabel,
    );

    final body = Padding(
      padding: EdgeInsets.fromLTRB(10, 10, onDelete != null ? 32 : 10, 10),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: onInverse.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(Icons.note_alt_outlined, color: onInverse),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: onInverse, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );

    final card = isGlass
        ? GlassSurface(
            variant: GlassVariant.card,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onTap,
              child: body,
            ),
          )
        : Material(
            color: onInverse.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onTap,
              child: body,
            ),
          );

    final onDeletePressed = onDelete;
    if (onDeletePressed == null) return card;

    return Stack(
      children: [
        card,
        Positioned(
          top: 4,
          right: 4,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onDeletePressed,
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: onInverse.withValues(alpha: 0.15),
              ),
              child: Icon(Icons.delete_outline, size: 14, color: onInverse),
            ),
          ),
        ),
      ],
    );
  }
}
