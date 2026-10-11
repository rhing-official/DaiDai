import 'dart:async';
import 'dart:convert';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../l10n/strings.dart';
import '../../models/app_ui_style.dart';
import '../../models/app_user.dart';
import '../../models/note.dart';
import '../../models/note_op.dart';
import '../../providers/app_ui_style_provider.dart';
import '../../providers/home_shell_providers.dart';
import '../../providers/repository_providers.dart';
import '../../utils/attachment_upload.dart';
import '../../utils/auto_dismiss_banner.dart';
import '../../utils/note_export.dart';
import '../../utils/note_transaction_codec.dart';
import '../../utils/platform_info.dart';
import '../../widgets/glass/glass_app_bar.dart';
import '../../widgets/glass/glass_bottom_sheet.dart';
import '../../widgets/glass/glass_dialog.dart';
import '../../widgets/interactive_swipe_back.dart';
import '../../widgets/swipe_gestures.dart';
import 'blocks/link_embed_block.dart';
import 'block_move_drag.dart';
import 'draw_canvas_view.dart';
import 'note_table_delete.dart';
import 'blocks/table_of_contents_block.dart';
import '../../widgets/dialog_keyboard_shortcuts.dart';

/// Obsidianの既定テーマに寄せた固定パレット（2026-09-26追加、ユーザー指示。
/// アクセントカラーに依存しない固定値という点で劇画UIの`GekigaColors`と
/// 同じ考え方）。ライト/ダーク双方を用意し、ダークは劇画（常にこの扱い）
/// にも適用する（元々のダーク文字色オーバーライドが劇画にも適用されていた
/// のを踏襲、2026-09-07導入時からの既存挙動）。
class _ObsidianNoteColors {
  const _ObsidianNoteColors({
    required this.background,
    required this.text,
    required this.mutedText,
    required this.accent,
    required this.selection,
    required this.divider,
  });

  final Color background;
  final Color text;
  final Color mutedText;
  final Color accent;
  // 選択ハイライト専用の色（2026-09-27追加）。以前はアクセントカラーに
  // 一律24%の透明度を掛けるだけだったが、暗い背景に低透明度の紫を重ねると
  // 選択範囲がほとんど視認できないほど薄くなる問題があったため、ライト/
  // ダークそれぞれで十分視認できる濃さを個別に指定する。
  final Color selection;
  final Color divider;

  static const dark = _ObsidianNoteColors(
    background: Color(0xFF1E1E1E),
    text: Color(0xFFDCDDDE),
    mutedText: Color(0xFF999999),
    accent: Color(0xFF8875FF),
    selection: Color(0x668875FF),
    divider: Color(0xFF3A3A3C),
  );

  static const light = _ObsidianNoteColors(
    background: Color(0xFFFFFFFF),
    text: Color(0xFF383A42),
    mutedText: Color(0xFF6C6C6C),
    accent: Color(0xFF7C3AED),
    selection: Color(0x4C7C3AED),
    divider: Color(0xFFE0E0E0),
  );
}

/// [_ObsidianNoteColors]から`EditorStyle.textStyleConfiguration`を組み立てる
/// （2026-09-26変更、以前はダーク時のみ白へ上書きする`_kNoteDarkText
/// StyleConfiguration`固定値だったが、ライトも含めてObsidian風パレットに
/// 統一した）。
TextStyleConfiguration _noteTextStyleConfiguration(_ObsidianNoteColors colors) {
  return TextStyleConfiguration(
    text: TextStyle(fontSize: 16, color: colors.text),
    href: TextStyle(color: colors.accent, decoration: TextDecoration.underline),
    code: TextStyle(
      color: colors.text,
      backgroundColor: colors.accent.withValues(alpha: 0.16),
    ),
    autoComplete: TextStyle(color: colors.mutedText),
    // 既定の取り消し線（decorationThickness未指定＝1.0倍）は細く視認性が低い
    // ため、太さを明示的に上げる（2026-09-27追加、ユーザー指示）。
    strikethrough: const TextStyle(
      decoration: TextDecoration.lineThrough,
      decorationThickness: 2.0,
    ),
  );
}

/// 共有ノートを寄合の表示領域内で全画面編集する（2026-09-06追加、
/// `CalendarPaneView`と同じ「ローカルなbool/String切り替えで中身を差し替える」
/// 方式、[onClose]呼び出し元がその切り替えを担う）。
///
/// エディタ本体は`appflowy_editor`（Notion風のブロックエディタ）。Markdown
/// ショートカット（`# `→見出し等、`standardCharacterShortcutEvents`）と
/// ツールバー・「/」挿入メニューのボタン操作は、どちらも同じ
/// `EditorState.apply(Transaction)`を介した内部コマンドを呼ぶ設計になって
/// おり、自作の「記号入力とボタンを同じ判定にする」処理は不要（詳細は
/// `_buildSelectionMenuItems`/`_buildToolbarItems`参照）。
///
/// リアルタイム共同編集（2026-09-09追加）: [NoteRepository.appendNoteOp]/
/// [NoteRepository.watchNoteOpsSince]による操作ログ（`notes/{noteId}/ops`）を
/// 介して、appflowy_editorの`Transaction`単位で他の参加者の編集を即座に
/// 反映する。[NoteRepository.updateNote]によるフルドキュメント上書きは
/// 「チェックポイント」として残し、編集停止から一定時間後・画面を閉じる際・
/// 操作ログが一定件数溜まった時・画面を開いて追いつき処理が終わった直後に
/// 実行し、その時点までの操作ログを[NoteRepository.pruneNoteOpsUpTo]で
/// 間引く。
class NotePaneView extends ConsumerStatefulWidget {
  const NotePaneView({
    required this.isDm,
    required this.conversationId,
    required this.roomId,
    required this.noteId,
    required this.currentUser,
    required this.onClose,
    super.key,
  });

  final bool isDm;
  final String conversationId;
  final String roomId;
  final String noteId;
  final AppUser currentUser;
  final VoidCallback onClose;

  @override
  ConsumerState<NotePaneView> createState() => _NotePaneViewState();
}

class _NotePaneViewState extends ConsumerState<NotePaneView>
    with WidgetsBindingObserver {
  EditorState? _editorState;

  /// エディタに選択（カーソル・範囲選択）があるか（2026-10-06追加）。選択の
  /// null/非nullが切り替わった時だけ通知する。モバイルの右スワイプで戻る操作は
  /// これがfalse（カーソル非表示）の間だけ有効にする（Obsidianと同様、
  /// 文中をタップするまでカーソルは出ない）。
  final ValueNotifier<bool> _caretVisible = ValueNotifier(false);

  /// モバイルでキーボードが一度開いたか。閉じた時にカーソルを消すための状態
  /// （[didChangeMetrics]）。
  bool _keyboardWasOpen = false;

  /// ドローノート（`Note.type == noteTypeDraw`）かどうか。読み込み完了までは
  /// false。種別は作成時に固定され、後から切り替わることはない。
  bool _isDraw = false;
  bool _noteLoaded = false;
  EditorScrollController? _scrollController;
  final _titleController = TextEditingController();
  final _titleFocusNode = FocusNode();
  // PC専用のカーソル行追従「+」ボタン（2026-09-27追加）の位置計算に使う、
  // エディタを包む`Stack`のキー。`_CursorLineAddButton`参照。
  final _editorStackKey = GlobalKey();
  StreamSubscription<EditorTransactionValue>? _transactionSub;
  StreamSubscription<List<NoteOp>>? _opsSub;
  Timer? _checkpointDebounce;
  Timer? _checkpointTimer;
  Timer? _sendDebounce;
  bool _dirty = false;
  bool _uploading = false;
  String _sessionId = '';
  Timestamp? _lastAppliedOpCreatedAt;
  bool _caughtUpInitialOps = false;
  int _opsSinceLastCheckpoint = 0;
  final List<Map<String, dynamic>> _pendingOutgoingTransactions = [];

  static const _checkpointDebounceDuration = Duration(milliseconds: 1500);
  static const _sendDebounceDuration = Duration(milliseconds: 350);
  static const _checkpointInterval = Duration(seconds: 30);
  static const _checkpointOpThreshold = 50;

  /// モバイル相当のUIを使うかどうか（2026-09-26変更）。以前は`Platform.
  /// isAndroid/isIOS`のみで判定しておりWeb版（`kIsWeb`）を一切考慮しない
  /// ため、モバイル端末のブラウザからWeb版を開いた場合にPC相当のUI
  /// （`FloatingToolbar`）のままになってしまっていた。DaiDaiの他画面
  /// （`talks_tab.dart`等）と同じ`classifyDevice`（画面幅・アスペクト比
  /// 併用、ネイティブ/Web問わず同じ結果になる）に揃える。
  bool get _isMobilePlatform => classifyDevice(context) != DeviceClass.computer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _titleFocusNode.addListener(
      () => _debugCaret('title focus=${_titleFocusNode.hasFocus}'),
    );
    _load();
  }

  void _onSelectionChanged() {
    final visible = _editorState?.selection != null;
    if (_caretVisible.value != visible) _caretVisible.value = visible;
    _debugCaret(
      'selection changed: ${_editorState?.selection} '
      'reason=${_editorState?.selectionUpdateReason}',
    );
  }

  // [NOTE-CARET]: 「ノートを開いた直後にカーソルが出る」原因調査用の一時ログ
  // （原因特定後に削除する）。
  void _debugCaret(String message) {
    if (kDebugMode) {
      debugPrint('[NOTE-CARET] ${DateTime.now().toIso8601String()} $message');
    }
  }

  /// モバイルでソフトキーボードを閉じたら、カーソルも消す（2026-10-06追加、
  /// ユーザー指示。Obsidianの「編集を終えるとカーソルが無い状態に戻る」を
  /// 模倣し、右スワイプで戻れる状態に戻すため）。キーボードが開いた後に
  /// 閉じた場合のみ。PC・Webのデスクトップはカーソルを出したままにする。
  @override
  void didChangeMetrics() {
    if (!mounted) return;
    final open = View.of(context).viewInsets.bottom > 0;
    if (open) {
      _keyboardWasOpen = true;
      return;
    }
    if (!_keyboardWasOpen) return;
    _keyboardWasOpen = false;
    if (_isMobilePlatform && _editorState?.selection != null) {
      _debugCaret('keyboard closed: clear selection');
      _editorState!.selection = null;
    }
  }

  Future<void> _load() async {
    // ネットワークアクセス無しでランダムIDを生成するトリック（自動採番される
    // ドキュメントIDをローカルで確定させるだけで、実際には書き込まない）。
    // このノートを開いている間、操作ログのエコー判定に使う。
    _sessionId = FirebaseFirestore.instance.collection('_').doc().id;
    final noteRepository = ref.read(noteRepositoryProvider);
    final note = await noteRepository.getNote(
      isDm: widget.isDm,
      conversationId: widget.conversationId,
      roomId: widget.roomId,
      noteId: widget.noteId,
    );
    if (!mounted) return;
    _titleController.text = note?.title ?? '';
    _lastAppliedOpCreatedAt = note?.updatedAt;
    if (note?.type == noteTypeDraw) {
      // ドローノートはappflowyエディタ・操作ログを使わない（線は
      // `DrawCanvasView`が`strokes`サブコレクションで同期する）。
      setState(() {
        _isDraw = true;
        _noteLoaded = true;
      });
      return;
    }
    final document = note != null && note.content.isNotEmpty
        ? Document.fromJson(note.content)
        : Document.blank(withInitialText: true);
    final editorState = EditorState(document: document);
    editorState.selectionNotifier.addListener(_onSelectionChanged);
    _debugCaret('editor created, selection=${editorState.selection}');
    _transactionSub = editorState.transactionStream.listen(
      _handleLocalTransaction,
    );
    setState(() {
      _noteLoaded = true;
      _editorState = editorState;
      _scrollController = EditorScrollController(
        editorState: editorState,
        shrinkWrap: false,
      );
    });
    debugPrint(
      '[note-sync] subscribing ops, sessionId=$_sessionId, '
      'afterCreatedAt=$_lastAppliedOpCreatedAt',
    );
    _opsSub = noteRepository
        .watchNoteOpsSince(
          isDm: widget.isDm,
          conversationId: widget.conversationId,
          roomId: widget.roomId,
          noteId: widget.noteId,
          afterCreatedAt: _lastAppliedOpCreatedAt,
        )
        .listen(
          _handleIncomingOps,
          onError: (Object e, StackTrace st) {
            debugPrint('[note-sync] ops stream ERROR: $e\n$st');
          },
        );
    _checkpointTimer = Timer.periodic(
      _checkpointInterval,
      (_) => _checkpointAndPrune(),
    );
  }

  void _handleLocalTransaction(EditorTransactionValue event) {
    final (time, transaction, _) = event;
    if (time != TransactionTime.after) return;
    _pendingOutgoingTransactions.add(encodeTransaction(transaction));
    _sendDebounce?.cancel();
    _sendDebounce = Timer(_sendDebounceDuration, _flushOutgoing);
    _scheduleCheckpoint();
  }

  Future<void> _flushOutgoing() {
    if (_pendingOutgoingTransactions.isEmpty) return Future.value();
    final batch = List<Map<String, dynamic>>.of(_pendingOutgoingTransactions);
    _pendingOutgoingTransactions.clear();
    debugPrint(
      '[note-sync] sending ${batch.length} transaction(s), '
      'sessionId=$_sessionId',
    );
    return ref
        .read(noteRepositoryProvider)
        .appendNoteOp(
          isDm: widget.isDm,
          conversationId: widget.conversationId,
          roomId: widget.roomId,
          noteId: widget.noteId,
          transactions: batch,
          sessionId: _sessionId,
          authorId: widget.currentUser.userId,
        )
        .then((_) => debugPrint('[note-sync] send succeeded'))
        .catchError((Object e, StackTrace st) {
          debugPrint('[note-sync] send FAILED: $e\n$st');
        });
  }

  /// 受信した操作ログを、自分が送信したもの（[NoteOp.sessionId]が自分と一致）
  /// を除いて`EditorState.apply(isRemote: true)`で適用する。ウォーターマーク
  /// [_lastAppliedOpCreatedAt]は自分のop含め全件で前進させ、間引きの判定に使う。
  void _handleIncomingOps(List<NoteOp> ops) {
    final editorState = _editorState;
    debugPrint(
      '[note-sync] received ${ops.length} op(s), '
      'mySessionId=$_sessionId, watermark=$_lastAppliedOpCreatedAt, '
      'editorStateNull=${editorState == null}',
    );
    if (editorState == null) return;
    final isInitialCatchUp = !_caughtUpInitialOps;
    _caughtUpInitialOps = true;
    for (final op in ops) {
      final createdAt = op.createdAt;
      if (createdAt != null &&
          _lastAppliedOpCreatedAt != null &&
          createdAt.compareTo(_lastAppliedOpCreatedAt!) <= 0) {
        debugPrint(
          '[note-sync] skip op (already applied): '
          'opSessionId=${op.sessionId}, createdAt=$createdAt',
        );
        continue;
      }
      if (op.sessionId != _sessionId) {
        debugPrint(
          '[note-sync] applying op from sessionId=${op.sessionId}, '
          '${op.transactions.length} transaction(s)',
        );
        for (final txJson in op.transactions) {
          try {
            final transaction = decodeTransaction(editorState.document, txJson);
            editorState.apply(transaction, isRemote: true);
            debugPrint('[note-sync] apply OK: $txJson');
          } catch (e, st) {
            debugPrint('[note-sync] apply FAILED: $e\n$txJson\n$st');
          }
        }
      } else {
        debugPrint('[note-sync] skip op (own echo): sessionId=${op.sessionId}');
      }
      if (createdAt != null) _lastAppliedOpCreatedAt = createdAt;
      _opsSinceLastCheckpoint++;
    }
    if ((isInitialCatchUp && ops.isNotEmpty) ||
        _opsSinceLastCheckpoint >= _checkpointOpThreshold) {
      _checkpointAndPrune();
    }
  }

  void _scheduleCheckpoint() {
    _dirty = true;
    _checkpointDebounce?.cancel();
    _checkpointDebounce = Timer(
      _checkpointDebounceDuration,
      _checkpointAndPrune,
    );
  }

  /// フルドキュメントのチェックポイント保存（[NoteRepository.updateNote]）と、
  /// それより古い操作ログの間引き（[NoteRepository.pruneNoteOpsUpTo]）を行う。
  /// 間引きの安全性は「既に確定済みのopのcreatedAt（[_lastAppliedOpCreatedAt]）
  /// より前は、このチェックポイントの内容に反映済み」という前提に依るため、
  /// ここでのチェックポイント保存は`_dirty`の有無に関わらず常に行う（他人の
  /// 編集を受信しただけで自分は未編集の場合でも、間引き前には必ず最新の
  /// マージ済み内容を書き込む）。
  Future<void> _checkpointAndPrune() async {
    _checkpointDebounce?.cancel();
    final editorState = _editorState;
    if (_isDraw) {
      // ドローノートはタイトルだけを保存する（本文`content`は空のまま）。
      if (!_dirty) return;
      _dirty = false;
      await ref
          .read(noteRepositoryProvider)
          .updateNote(
            isDm: widget.isDm,
            conversationId: widget.conversationId,
            roomId: widget.roomId,
            noteId: widget.noteId,
            title: _titleController.text,
            content: const {},
            editedBy: widget.currentUser.userId,
          );
      return;
    }
    if (editorState == null) return;
    _dirty = false;
    final noteRepository = ref.read(noteRepositoryProvider);
    final watermark = _lastAppliedOpCreatedAt;
    await noteRepository.updateNote(
      isDm: widget.isDm,
      conversationId: widget.conversationId,
      roomId: widget.roomId,
      noteId: widget.noteId,
      title: _titleController.text,
      content: editorState.document.toJson(),
      editedBy: widget.currentUser.userId,
    );
    _opsSinceLastCheckpoint = 0;
    if (watermark != null) {
      await noteRepository.pruneNoteOpsUpTo(
        isDm: widget.isDm,
        conversationId: widget.conversationId,
        roomId: widget.roomId,
        noteId: widget.noteId,
        upToCreatedAtInclusive: watermark,
      );
    }
  }

  void _handleTitleChanged(String _) => _scheduleCheckpoint();

  Future<void> _close() async {
    _sendDebounce?.cancel();
    await _flushOutgoing();
    await _checkpointAndPrune();
    if (mounted) widget.onClose();
  }

  @override
  void dispose() {
    _checkpointDebounce?.cancel();
    _checkpointTimer?.cancel();
    _sendDebounce?.cancel();
    // dispose中は非同期await不可のため、確定済みの内容をfire-and-forgetで
    // 保存する（ページを閉じる通常経路は`_close`が先にawait済みのため、
    // ここに到達するのは想定外の破棄経路への保険）。次にこのノートを開いた
    // クライアントが追いつき処理の一環で操作ログの間引きも行うため、ここでは
    // 間引きまでは行わない。
    final editorState = _editorState;
    if (_dirty && _isDraw) {
      ref
          .read(noteRepositoryProvider)
          .updateNote(
            isDm: widget.isDm,
            conversationId: widget.conversationId,
            roomId: widget.roomId,
            noteId: widget.noteId,
            title: _titleController.text,
            content: const {},
            editedBy: widget.currentUser.userId,
          );
    } else if (_dirty && editorState != null) {
      ref
          .read(noteRepositoryProvider)
          .updateNote(
            isDm: widget.isDm,
            conversationId: widget.conversationId,
            roomId: widget.roomId,
            noteId: widget.noteId,
            title: _titleController.text,
            content: editorState.document.toJson(),
            editedBy: widget.currentUser.userId,
          );
    }
    if (_pendingOutgoingTransactions.isNotEmpty) {
      ref
          .read(noteRepositoryProvider)
          .appendNoteOp(
            isDm: widget.isDm,
            conversationId: widget.conversationId,
            roomId: widget.roomId,
            noteId: widget.noteId,
            transactions: _pendingOutgoingTransactions,
            sessionId: _sessionId,
            authorId: widget.currentUser.userId,
          );
    }
    WidgetsBinding.instance.removeObserver(this);
    _editorState?.selectionNotifier.removeListener(_onSelectionChanged);
    _caretVisible.dispose();
    _transactionSub?.cancel();
    _opsSub?.cancel();
    _scrollController?.dispose();
    _editorState?.dispose();
    _titleController.dispose();
    _titleFocusNode.dispose();
    super.dispose();
  }

  List<ToolbarItem> _buildToolbarItems() {
    const allowedFormatIds = {'editor.bold', 'editor.strikethrough'};
    return [
      ...headingItems.where((i) => i.id == 'editor.h2' || i.id == 'editor.h3'),
      ...markdownFormatItems.where((i) => allowedFormatIds.contains(i.id)),
      bulletedListItem,
      numberedListItem,
      quoteItem,
      linkItem,
    ];
  }

  /// [build]と同じ判定（2026-09-26追加）。ボトムシートを開くタイミングは
  /// `build`の外（`IconButton.onPressed`）のため、同じ配色計算を単独で
  /// 呼べるようgetterに切り出した。
  _ObsidianNoteColors get _noteColors {
    final uiStyle = ref.read(appUiStyleProvider);
    final isGekiga = uiStyle == AppUiStyle.gekiga;
    final isDark = isGekiga || Theme.of(context).brightness == Brightness.dark;
    return isDark ? _ObsidianNoteColors.dark : _ObsidianNoteColors.light;
  }

  /// モバイル用の挿入メニュー（2026-10-04追加、ユーザー指示）。PCの「+」
  /// （[_CursorLineAddButton]）／「/」メニューと同じ項目
  /// （[_buildSelectionMenuItems]）を、AppBarの「+」から開くボトムシートで
  /// 提供する。`appflowy_editor`の「/」メニューはモバイル不可のため、各項目の
  /// `handler`は`menuService`を使わない実装であることを利用し、PC用の
  /// `SelectionMenu`オーバーレイを介さず直接呼ぶ（`SelectionMenu`は
  /// `SelectionMenuService`を満たす値として渡すだけで`show()`は呼ばない）。
  /// 書式（太字等）は同日に廃止した「T」ボタンのボトムシートから、
  /// テキスト選択時のポップアップ（[_buildMobileSelectionToolbar]）へ移した。
  Future<void> _openInsertBottomSheet() async {
    final editorState = _editorState;
    if (editorState == null) return;
    final isGlass = ref.read(appUiStyleProvider) == AppUiStyle.glass;
    final strings = ref.read(appStringsProvider);
    // 「/」入力の後始末（直前の文字を消す処理）は挿入メニューを開いた
    // 経緯に依存するため、AppBarから開くここでは無効にする。PCの「+」が
    // `SelectionMenu.show()`内で行うのと同じ設定（`deleteSlashByDefault:
    // false`相当）を、`show()`を呼ばないこの経路では自前で適用する。
    final items = _buildSelectionMenuItems(strings)
      ..forEach((item) {
        item.deleteSlash = false;
        item.deleteKeywords = false;
      });
    final menu = SelectionMenu(
      context: context,
      editorState: editorState,
      selectionMenuItems: items,
      deleteSlashByDefault: false,
    );
    Widget builder(BuildContext sheetContext) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          for (final item in items)
            ListTile(
              leading: item.icon(
                editorState,
                false,
                Theme.of(sheetContext).brightness == Brightness.dark
                    ? SelectionMenuStyle.dark
                    : SelectionMenuStyle.light,
              ),
              title: Text(item.name),
              onTap: () {
                Navigator.of(sheetContext).pop();
                item.handler(editorState, menu, context);
              },
            ),
        ],
      ),
    );
    if (isGlass) {
      await showGlassModalBottomSheet<void>(context: context, builder: builder);
    } else {
      await showModalBottomSheet<void>(context: context, builder: builder);
    }
  }

  /// モバイルのテキスト選択ポップアップ（2026-10-04追加、ユーザー指示）。
  /// 範囲選択された時に[MobileFloatingToolbar]が[anchor]（選択範囲の上端
  /// 中央、グローバル座標）に呼ぶ。切り取り／コピー／貼り付けと、PCの選択
  /// ツールバーと同じ書式項目（[_buildToolbarItems]）を横並びで出す。
  Widget _buildMobileSelectionToolbar(
    BuildContext context,
    Offset anchor,
    VoidCallback closeToolbar,
    EditorState editorState,
  ) {
    final strings = ref.read(appStringsProvider);
    final noteColors = _noteColors;
    final formatItems = _buildToolbarItems()
        .where((item) => item.isActive?.call(editorState) ?? true)
        .toList();
    Widget textAction(String label, CommandShortcutEvent command) {
      return TextButton(
        style: TextButton.styleFrom(
          foregroundColor: noteColors.text,
          minimumSize: const Size(0, 36),
          padding: const EdgeInsets.symmetric(horizontal: 10),
        ),
        onPressed: () {
          command.handler(editorState);
          closeToolbar();
        },
        child: Text(label),
      );
    }

    final media = MediaQuery.of(context);
    const toolbarHeight = 44.0;
    const margin = 8.0;
    // 選択範囲の上に出し、上端に近ければ下へ回す。左右は画面内に収める。
    final top = anchor.dy - toolbarHeight - margin < media.padding.top
        ? anchor.dy + margin + 24
        : anchor.dy - toolbarHeight - margin;
    return Positioned(
      top: top,
      left: margin,
      right: margin,
      child: Align(
        alignment: Alignment.topCenter,
        child: Material(
          color: noteColors.background,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: noteColors.divider),
          ),
          child: SizedBox(
            height: toolbarHeight,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: StreamBuilder<EditorTransactionValue>(
                stream: editorState.transactionStream,
                builder: (context, _) {
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      textAction(strings.noteSelectionCut, cutCommand),
                      textAction(strings.noteSelectionCopy, copyCommand),
                      textAction(strings.noteSelectionPaste, pasteCommand),
                      for (final item in formatItems)
                        if (item.builder != null)
                          item.builder!(
                            context,
                            editorState,
                            noteColors.accent,
                            noteColors.text,
                            null,
                          ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<SelectionMenuItem> _buildSelectionMenuItems(Strings strings) {
    return [
      SelectionMenuItem(
        getName: () => strings.noteMenuHeading2,
        icon: (editorState, isSelected, style) => SelectionMenuIconWidget(
          name: 'h2',
          isSelected: isSelected,
          style: style,
        ),
        keywords: const ['heading2', 'h2'],
        handler: (editorState, _, _) =>
            insertHeadingAfterSelection(editorState, 2),
      ),
      SelectionMenuItem(
        getName: () => strings.noteMenuHeading3,
        icon: (editorState, isSelected, style) => SelectionMenuIconWidget(
          name: 'h3',
          isSelected: isSelected,
          style: style,
        ),
        keywords: const ['heading3', 'h3'],
        handler: (editorState, _, _) =>
            insertHeadingAfterSelection(editorState, 3),
      ),
      SelectionMenuItem(
        getName: () => strings.noteMenuBulletedList,
        icon: (editorState, isSelected, style) => SelectionMenuIconWidget(
          name: 'bulleted_list',
          isSelected: isSelected,
          style: style,
        ),
        keywords: const ['bulleted list', 'list'],
        handler: (editorState, _, _) =>
            insertBulletedListAfterSelection(editorState),
      ),
      SelectionMenuItem(
        getName: () => strings.noteMenuNumberedList,
        icon: (editorState, isSelected, style) => SelectionMenuIconWidget(
          name: 'number',
          isSelected: isSelected,
          style: style,
        ),
        keywords: const ['numbered list', 'list'],
        handler: (editorState, _, _) =>
            insertNumberedListAfterSelection(editorState),
      ),
      SelectionMenuItem(
        getName: () => strings.noteMenuQuote,
        icon: (editorState, isSelected, style) => SelectionMenuIconWidget(
          name: 'quote',
          isSelected: isSelected,
          style: style,
        ),
        keywords: const ['quote'],
        handler: (editorState, _, _) => insertQuoteAfterSelection(editorState),
      ),
      dividerMenuItem,
      // 表・目次（2026-09-27追加、ユーザー指示）。表はベンダリング済みAppFlowy
      // Editorに既に実装があり（`blockComponentBuilders`はデフォルトの
      // `standardBlockComponentBuilderMap`を継承しているため編集自体は
      // 既に機能する）、メニューからの挿入導線が無かっただけ。目次は
      // `blocks/table_of_contents_block.dart`の新規カスタムブロック。
      SelectionMenuItem(
        getName: () => strings.noteMenuTable,
        icon: (editorState, isSelected, style) => Icon(
          Icons.table_chart_outlined,
          size: 18.0,
          color: isSelected
              ? style.selectionMenuItemSelectedIconColor
              : style.selectionMenuItemIconColor,
        ),
        keywords: const ['table'],
        handler: (editorState, _, _) => _promptAndInsertTable(),
      ),
      SelectionMenuItem(
        getName: () => strings.noteMenuTableOfContents,
        icon: (editorState, isSelected, style) => Icon(
          Icons.toc,
          size: 18.0,
          color: isSelected
              ? style.selectionMenuItemSelectedIconColor
              : style.selectionMenuItemIconColor,
        ),
        keywords: const ['table of contents', 'toc', 'outline'],
        handler: (editorState, _, _) =>
            insertNodeAfterSelection(editorState, tableOfContentsNode()),
      ),
      // 添付ファイルは以前「画像/動画/ファイル」の3択ポップアップ1項目
      // だったが、参考画像の構成に合わせて画像/音声/ファイルを独立した項目に
      // 分割した（2026-09-27変更、ユーザー指示。AppBarの📎ボタン経由の
      // 3択ポップアップ`_pickAndInsertAttachment`はそのまま残す）。
      // 動画専用の項目は無くなるが、`_insertAttachment`は元々画像以外を
      // 全て同じリンク挿入として扱っていたため機能的な後退は無い。
      SelectionMenuItem(
        getName: () => strings.noteMenuImage,
        icon: (editorState, isSelected, style) => SelectionMenuIconWidget(
          name: 'image',
          isSelected: isSelected,
          style: style,
        ),
        keywords: const ['image'],
        handler: (editorState, _, _) => _pickAndInsertImage(),
      ),
      SelectionMenuItem(
        getName: () => strings.noteMenuAudio,
        icon: (editorState, isSelected, style) => Icon(
          Icons.audiotrack_outlined,
          size: 18.0,
          color: isSelected
              ? style.selectionMenuItemSelectedIconColor
              : style.selectionMenuItemIconColor,
        ),
        keywords: const ['audio'],
        handler: (editorState, _, _) => _pickAndInsertAudio(),
      ),
      SelectionMenuItem(
        getName: () => strings.noteMenuFile,
        icon: (editorState, isSelected, style) => Icon(
          Icons.attach_file,
          size: 18.0,
          color: isSelected
              ? style.selectionMenuItemSelectedIconColor
              : style.selectionMenuItemIconColor,
        ),
        keywords: const ['file'],
        handler: (editorState, _, _) => _pickAndInsertGenericFile(),
      ),
      SelectionMenuItem(
        getName: () => strings.noteMenuEmbed,
        icon: (editorState, isSelected, style) => Icon(
          Icons.link,
          size: 18.0,
          color: isSelected
              ? style.selectionMenuItemSelectedIconColor
              : style.selectionMenuItemIconColor,
        ),
        keywords: const ['embed', 'url', 'link'],
        handler: (editorState, _, _) => _promptAndInsertEmbed(strings),
      ),
    ];
  }

  /// 「+」メニュー・「/」メニュー専用の画像選択（2026-09-27追加）。AppBarの
  /// 📎ボタン用の3択ポップアップ（`_pickAndInsertAttachment`）とは別に、
  /// 参考画像の構成に合わせて単独タップで直接実行する。
  Future<void> _pickAndInsertImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    await _insertAttachment(
      bytes: await picked.readAsBytes(),
      fileName: picked.name,
      contentType: 'image',
    );
  }

  Future<void> _pickAndInsertAudio() async {
    final file = await FilePicker.pickFile(type: FileType.audio);
    if (file == null) return;
    await _insertAttachment(
      bytes: await file.readAsBytes(),
      fileName: file.name,
      contentType: 'audio',
    );
  }

  Future<void> _pickAndInsertGenericFile() async {
    final file = await FilePicker.pickFile();
    if (file == null) return;
    await _insertAttachment(
      bytes: await file.readAsBytes(),
      fileName: file.name,
      contentType: 'file',
    );
  }

  /// URLを入力してもらい、`LinkEmbedBlockKeys`ノードとして挿入する
  /// （2026-09-27追加、ユーザー指示）。OGP取得自体は`LinkPreviewCard`が
  /// 表示時に`linkPreviewProvider`経由で行うため、ここではURLの確定のみ行う。
  Future<void> _promptAndInsertEmbed(Strings strings) async {
    final editorState = _editorState;
    if (editorState == null) return;
    final isGlass = ref.read(appUiStyleProvider) == AppUiStyle.glass;
    final controller = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        final title = Text(strings.noteEmbedUrlPromptTitle);
        final content = TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: InputDecoration(hintText: strings.noteEmbedUrlPromptHint),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        );
        final actions = [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(strings.cancel),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: Text(strings.noteEmbedUrlPromptConfirm),
          ),
        ];
        return isGlass
            ? GlassAlertDialog(title: title, content: content, actions: actions)
            : KeyboardAlertDialog(
                title: title,
                content: content,
                actions: actions,
              );
      },
    );
    if (url == null || url.trim().isEmpty || !mounted) return;
    insertNodeAfterSelection(editorState, linkEmbedNode(url: url.trim()));
  }

  /// 表のマス目プレビューを表示し、選択された縦横比でその場で表を挿入する
  /// （2026-09-27追加、ユーザー指示。Notion等の表挿入UIを参考にした）。
  /// `_TableSizePicker`はマスをクリックした瞬間に確定する（別途「作成」
  /// ボタンは置かない）。
  Future<void> _promptAndInsertTable() async {
    final editorState = _editorState;
    if (editorState == null) return;
    final noteColors = _noteColors;
    final isGlass = ref.read(appUiStyleProvider) == AppUiStyle.glass;
    final size = await showDialog<(int, int)>(
      context: context,
      builder: (dialogContext) {
        final content = _TableSizePicker(
          accentColor: noteColors.accent,
          neutralColor: noteColors.divider,
        );
        return isGlass
            ? GlassAlertDialog(content: content)
            : KeyboardAlertDialog(content: content);
      },
    );
    if (size == null || !mounted) return;
    final (rows, columns) = size;
    insertNodeAfterSelection(
      editorState,
      TableNode.fromList<String>(
        List.generate(columns, (_) => List.generate(rows, (_) => '')),
      ).node,
    );
  }

  String get _storagePathPrefix =>
      'noteAttachments/${widget.isDm ? 'dm' : 'group'}/${widget.conversationId}';

  Future<void> _insertAttachment({
    required Uint8List bytes,
    required String fileName,
    required String contentType,
  }) async {
    final editorState = _editorState;
    if (editorState == null || _uploading) return;
    setState(() => _uploading = true);
    try {
      final metadata = await uploadMessageAttachment(
        storage: FirebaseStorage.instance,
        storagePathPrefix: _storagePathPrefix,
        attachmentId:
            '${widget.noteId}_${DateTime.now().microsecondsSinceEpoch}',
        bytes: bytes,
        fileName: fileName,
        contentType: contentType,
      );
      if (contentType == 'image') {
        await editorState.insertImageNode(metadata.url);
      } else {
        // 動画・ファイルはappflowy_editor組み込みの画像ブロックが対応
        // しないため、ファイル名をリンク（href=Storage URL）にした段落として
        // 挿入する（タップで開ける、既存のリッチテキストのリンク機能を
        // そのまま使う簡易な実装）。
        insertNodeAfterSelection(
          editorState,
          paragraphNode(
            delta: Delta()
              ..insert('📎 $fileName', attributes: {'href': metadata.url}),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  /// ダウンロード（2026-10-04追加、以前の添付ボタンの位置）。マークダウンは
  /// `.md`、ドローは白背景の`.png`で端末へ保存する。
  Future<void> _download() async {
    final strings = ref.read(appStringsProvider);
    final baseName = sanitizeFileName(
      _titleController.text,
      strings.noteDownloadDefaultName,
    );
    try {
      if (_isDraw) {
        final strokes = await ref
            .read(noteRepositoryProvider)
            .watchStrokes(
              isDm: widget.isDm,
              conversationId: widget.conversationId,
              roomId: widget.roomId,
              noteId: widget.noteId,
            )
            .first;
        final png = await renderStrokesToPng(strokes);
        if (!mounted) return;
        if (png == null) {
          showAutoDismissBanner(
            context,
            message: strings.noteDrawNothingToExport,
          );
          return;
        }
        await saveNoteFile(
          fileName: '$baseName.png',
          bytes: png,
          mimeType: 'image/png',
        );
      } else {
        final editorState = _editorState;
        if (editorState == null) return;
        final markdown = documentToMarkdown(editorState.document);
        await saveNoteFile(
          fileName: '$baseName.md',
          bytes: Uint8List.fromList(utf8.encode(markdown)),
          mimeType: 'text/markdown',
        );
      }
    } catch (e) {
      debugPrint('[note-download] failed: $e');
      if (mounted) {
        showAutoDismissBanner(context, message: strings.noteDownloadFailed);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 語らいタブ以外（身だしなみ・設定）に切り替わった際、選択中のまま残った
    // `FloatingToolbar`が最前面に描画され続ける不具合の修正（2026-09-27
    // 追加、ユーザー指示）。`HomeScreen`は3タブとも`IndexedStack`で常時
    // マウントし続けるため、`NotePaneView`自体は破棄されず選択も維持され、
    // `FloatingToolbar`自身の「選択が無くなったら隠れる」既存ロジックが
    // 発動する機会が無かった。既存の`homeSelectedTabProvider`
    // （`lib/providers/home_shell_providers.dart`、通話ピン留めミニ表示が
    // 同じ目的で既に使っている「今どのタブを見ているか」のミラー）を監視し、
    // 語らいタブで無くなった瞬間にエディタの選択を解除する。
    ref.listen<int>(homeSelectedTabProvider, (previous, next) {
      if (next != kTalksTabIndex) {
        _editorState?.selection = null;
      }
    });
    final strings = ref.watch(appStringsProvider);
    final uiStyle = ref.watch(appUiStyleProvider);
    final isGlass = uiStyle == AppUiStyle.glass;
    // ライトモードもappflowy_editor既定の黒のままにせず、Obsidian風パレット
    // に統一する（2026-09-26変更、ユーザー指示。ダーク時（劇画は常時この
    // 扱い）は元々白へ上書きしていたのを踏襲）。
    final noteColors = _noteColors;
    final isMobile = _isMobilePlatform;

    final leadingButton = IconButton(
      icon: const Icon(Icons.arrow_back),
      tooltip: '',
      onPressed: _close,
    );
    final titleField = TextField(
      controller: _titleController,
      focusNode: _titleFocusNode,
      onChanged: _handleTitleChanged,
      style: Theme.of(context).textTheme.titleMedium,
      decoration: InputDecoration(
        hintText: strings.noteTitleFieldHint,
        border: InputBorder.none,
      ),
    );
    final downloadAction = IconButton(
      icon: const Icon(Icons.download),
      tooltip: '',
      onPressed: !_noteLoaded ? null : _download,
    );
    // モバイル専用の挿入ボタン（2026-10-04追加、ユーザー指示）。PCの「+」
    // /「/」メニューが使えないため、AppBarからボトムシートで同じ項目を開く
    // （`_openInsertBottomSheet`参照）。書式は選択時ポップアップへ移した。
    final insertAction = IconButton(
      icon: const Icon(Icons.add),
      tooltip: strings.noteInsertTooltip,
      onPressed: _editorState == null ? null : () => _openInsertBottomSheet(),
    );

    // タイトル欄（appBar側の`titleField`）にフォーカスがある間にEscを押した
    // 場合も閉じられるよう、`Scaffold.body`だけでなく`appBar`も含めて
    // `Focus`で包む（appBarとbodyはフォーカスツリー上兄弟のため、body側だけ
    // 包んでもタイトル欄フォーカス中はこのハンドラの祖先チェーンに入らない、
    // 2026-09-07変更）。
    final page = Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.escape) {
          _close();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Scaffold(
        backgroundColor: noteColors.background,
        appBar: isGlass
            ? GlassAppBar(
                leading: leadingButton,
                title: titleField,
                actions: [
                  if (isMobile && !_isDraw) insertAction,
                  downloadAction,
                ],
              )
            : AppBar(
                backgroundColor: noteColors.background,
                foregroundColor: noteColors.text,
                leading: leadingButton,
                title: titleField,
                actions: [
                  if (isMobile && !_isDraw) insertAction,
                  downloadAction,
                ],
              ),
        // 下スワイプで閉じる（既存）。右スワイプは画面全体（AppBar込み）を
        // `InteractiveSwipeBackTransition`で包む（下の`return`参照）。
        body: SwipeDownToDismiss(
          onDismiss: _close,
          // ドローノートは矢印とEscでしか閉じない（2026-10-10、ユーザー指示。
          // ペンで下へなぞって誤って閉じるのを防ぐ）。
          enabled: !_isDraw,
          child: _isDraw
              ? DrawCanvasView(
                  isDm: widget.isDm,
                  conversationId: widget.conversationId,
                  roomId: widget.roomId,
                  noteId: widget.noteId,
                  currentUser: widget.currentUser,
                  foreground: noteColors.text,
                  background: noteColors.background,
                )
              : _buildEditorBody(strings, noteColors, isMobile),
        ),
      ),
    );
    // 右スワイプで閉じる操作は、設定・身だしなみ・チャットと同じ指追従の
    // `InteractiveSwipeBackTransition`（2026-10-07、以前は離散的な
    // `SwipeBackDetector`でアニメーションが無かった）。モバイルのみ・ドロー
    // 以外（ペンの横ストロークで誤って閉じるため）・カーソル（選択）が無い間
    // だけ有効（2026-10-06、ユーザー指示）。表の横操作は表側
    // （third_party table_block_component）で吸収している。エディタ（child）は
    // 再生成しない。流れた後ろには`DmChatPane`/`GroupChatPane`が
    // `SlideDrilldown`で残しているメッセージ画面が見える。
    return ValueListenableBuilder<bool>(
      valueListenable: _caretVisible,
      builder: (context, caretVisible, child) => InteractiveSwipeBackTransition(
        enabled: isMobile && !_isDraw && !caretVisible,
        onBack: _close,
        child: child!,
      ),
      // ドローノートは、メッセージ画面のルート全体の右スワイプ戻る等の外側の
      // 水平スワイプも受けないよう、水平ドラッグを吸収する（2026-10-10、
      // `HorizontalDragAbsorber`参照）。閉じる手段は左上の矢印とEscのみ。
      child: _isDraw ? HorizontalDragAbsorber(child: page) : page,
    );
  }

  Widget _buildEditorBody(
    Strings strings,
    _ObsidianNoteColors noteColors,
    bool isMobile,
  ) {
    final editorState = _editorState;
    final scrollController = _scrollController;
    if (editorState == null || scrollController == null) {
      return const SizedBox.shrink();
    }
    // 「/」入力メニュー（note.comの「+」ボタンに相当）はappflowy_editorの
    // 仕様上デスクトップ/Web限定（`slash_command.dart`のPlatformExtension.
    // isMobileガード参照）。標準の`slashCommand`を、v1で対応する項目だけに
    // 絞った`customSlashCommand`に差し替える。
    final characterShortcutEvents = [
      customSlashCommand(_buildSelectionMenuItems(strings)),
      ...standardCharacterShortcutEvents.where((e) => e != slashCommand),
    ];
    final textStyleConfiguration = _noteTextStyleConfiguration(noteColors);
    // 区切り線のみObsidian風パレットに合わせて色を差し替える（2026-09-26
    // 追加）。他は`standardBlockComponentBuilderMap`のまま。
    final blockComponentBuilders = {
      ...standardBlockComponentBuilderMap,
      DividerBlockKeys.type: DividerBlockComponentBuilder(
        configuration: standardBlockComponentConfiguration.copyWith(
          padding: (node) => const EdgeInsets.symmetric(vertical: 8.0),
        ),
        lineColor: noteColors.divider,
      ),
      // 埋め込み・目次（2026-09-27追加、ユーザー指示）。
      LinkEmbedBlockKeys.type: LinkEmbedBlockComponentBuilder(),
      TableOfContentsBlockKeys.type: TableOfContentsBlockComponentBuilder(),
      // 表の左上の角に、表全体を文書内の別の位置へ移動するドラッグハンドルを
      // 置く（2026-10-04追加、ユーザー指示。行/列の並び替えハンドルとは別）。
      TableBlockKeys.type: TableBlockComponentBuilder(
        cornerHandleBuilder: (context, node) => BlockMoveHandle(
          node: node,
          editorState: editorState,
          color: noteColors.text.withValues(alpha: 0.55),
          tooltip: strings.noteBlockMoveTooltip,
        ),
      ),
      // 表の1行目（見出し行）を常に太字にする（2026-09-27追加、ユーザー指示）。
      // 段落ノードの`parent`が表のセル（`rowPosition == 0`）かどうかで判定する
      // ため、テーブル外の通常の段落には影響しない。
      ParagraphBlockKeys.type: ParagraphBlockComponentBuilder(
        configuration: standardBlockComponentConfiguration.copyWith(
          textStyle: (node, {textSpan}) {
            final parent = node.parent;
            if (parent != null &&
                parent.type == TableCellBlockKeys.type &&
                parent.attributes[TableCellBlockKeys.rowPosition] == 0) {
              return const TextStyle(fontWeight: FontWeight.bold);
            }
            return const TextStyle();
          },
        ),
      ),
    };
    final editor = AppFlowyEditor(
      editorState: editorState,
      editorScrollController: scrollController,
      // モバイル判定のWeb版は、appflowy_editorがisDesktopOrWebでデスクトップ用の
      // 選択処理を使い、指を置いた瞬間にカーソル・ドラッグ選択が作られて右スワイプ
      // で閉じる操作（`SwipeBackDetector`）が負けていた（2026-10-07修正）。
      // モバイルのみ押下即時のドラッグ選択を切り、水平スワイプを先に勝たせる。
      enablePanImmediate: !isMobile,
      editorStyle: isMobile
          ? EditorStyle.mobile(
              textStyleConfiguration: textStyleConfiguration,
              cursorColor: noteColors.accent,
              selectionColor: noteColors.selection,
            )
          : EditorStyle.desktop(
              textStyleConfiguration: textStyleConfiguration,
              cursorColor: noteColors.accent,
              selectionColor: noteColors.selection,
            ),
      characterShortcutEvents: characterShortcutEvents,
      // 標準の`exitEditingCommand`（Escapeキー）は選択解除・ソフトキーボード
      // を閉じるだけで`KeyEventResult.handled`を返すため、エディタ本体に
      // フォーカスがある間はEscapeキーがここで消費されてしまい、外側の
      // `Focus.onKeyEvent`（`_close()`でノートを閉じる）まで伝播しなかった
      // （2026-09-07判明）。「/」入力メニューの`slashCommand`除外と同じ要領で
      // 除外し、Escapeを外側へ伝播させる。
      // 表の全セルを覆う範囲選択でのBackspace/Deleteは表ごと消す
      // （`note_table_delete.dart`、標準のコマンドより前に置く）。
      commandShortcutEvents: [
        wholeTableBackspaceCommand,
        wholeTableDeleteCommand,
        ...standardCommandShortcutEvents.where((e) => e != exitEditingCommand),
      ],
      blockComponentBuilders: blockComponentBuilders,
    );
    // モバイル: テキスト選択時にポップアップ（切り取り/コピー/貼り付け＋
    // 書式）を出す（2026-10-04変更、ユーザー指示。以前は「T」の書式ボタン
    // からボトムシートを開く方式だったが廃止）。挿入はAppBarの「+」。
    if (isMobile) {
      return MobileFloatingToolbar(
        editorState: editorState,
        editorScrollController: scrollController,
        floatingToolbarHeight: 44,
        toolbarBuilder: (context, anchor, closeToolbar) =>
            _buildMobileSelectionToolbar(
              context,
              anchor,
              closeToolbar,
              editorState,
            ),
        child: editor,
      );
    }
    // PC専用: カーソルが乗っている行の右端に常設の「+」を表示し、「/」入力と
    // 同じ挿入メニューをクリックだけで開けるようにする（2026-09-27追加、
    // ユーザー指示。note.com等を参考にしたNotion風の導線）。
    // `FloatingToolbar`とは独立に、同じ`Stack`内へ重ねて表示する。
    return Stack(
      key: _editorStackKey,
      children: [
        FloatingToolbar(
          items: _buildToolbarItems(),
          editorState: editorState,
          editorScrollController: scrollController,
          textDirection: TextDirection.ltr,
          style: FloatingToolbarStyle(
            backgroundColor: noteColors.background,
            toolbarActiveColor: noteColors.accent,
            toolbarIconColor: noteColors.text,
          ),
          child: editor,
        ),
        _CursorLineAddButton(
          editorState: editorState,
          editorScrollController: scrollController,
          stackKey: _editorStackKey,
          iconColor: noteColors.text,
          onPressed: () => SelectionMenu(
            context: context,
            editorState: editorState,
            selectionMenuItems: _buildSelectionMenuItems(strings),
            deleteSlashByDefault: false,
          ).show(),
        ),
      ],
    );
  }
}

/// PC専用、カーソルが乗っている行の右端に追従する「+」ボタン
/// （2026-09-27追加、ユーザー指示）。`editorState.selectionRects()`
/// （`FloatingToolbar`が自身の位置決めに使うのと同じ公開API）でカーソルの
/// 矩形（グローバル座標）を取得し、[stackKey]が指す`Stack`のローカル座標へ
/// 変換して`Positioned`で重ねる。選択がcollapsed（カーソルのみ、ドラッグ
/// 選択中でない）の間だけ表示する。
class _CursorLineAddButton extends StatefulWidget {
  const _CursorLineAddButton({
    required this.editorState,
    required this.editorScrollController,
    required this.stackKey,
    required this.iconColor,
    required this.onPressed,
  });

  final EditorState editorState;
  final EditorScrollController editorScrollController;
  final GlobalKey stackKey;
  final Color iconColor;
  final VoidCallback onPressed;

  @override
  State<_CursorLineAddButton> createState() => _CursorLineAddButtonState();
}

class _CursorLineAddButtonState extends State<_CursorLineAddButton> {
  Rect? _cursorRect;

  @override
  void initState() {
    super.initState();
    widget.editorState.selectionNotifier.addListener(_recompute);
    widget.editorScrollController.offsetNotifier.addListener(_recompute);
    WidgetsBinding.instance.addPostFrameCallback((_) => _recompute());
  }

  @override
  void dispose() {
    widget.editorState.selectionNotifier.removeListener(_recompute);
    widget.editorScrollController.offsetNotifier.removeListener(_recompute);
    super.dispose();
  }

  void _recompute() {
    if (!mounted) return;
    final selection = widget.editorState.selection;
    if (selection == null || !selection.isCollapsed) {
      setState(() => _cursorRect = null);
      return;
    }
    final rects = widget.editorState.selectionRects();
    if (rects.isEmpty) {
      setState(() => _cursorRect = null);
      return;
    }
    final stackBox = widget.stackKey.currentContext?.findRenderObject();
    if (stackBox is! RenderBox || !stackBox.attached) {
      setState(() => _cursorRect = null);
      return;
    }
    final globalRect = rects.first;
    setState(() {
      _cursorRect =
          stackBox.globalToLocal(globalRect.topLeft) & globalRect.size;
    });
  }

  @override
  Widget build(BuildContext context) {
    final rect = _cursorRect;
    if (rect == null) return const SizedBox.shrink();
    const buttonSize = 26.0;
    const gapFromText = 8.0;
    // 本文が実際に始まる位置（エディタの左余白）のすぐ手前にボタンが来る
    // よう、固定の8pxではなくエディタ自身の左パディングから逆算する
    // （2026-09-27修正、デスクトップは既定で左右100pxの余白があるため）。
    final left =
        (widget.editorState.editorStyle.padding.left - buttonSize - gapFromText)
            .clamp(0.0, double.infinity);
    return Positioned(
      top: rect.top + (rect.height - buttonSize) / 2,
      left: left,
      child: SizedBox(
        width: buttonSize,
        height: buttonSize,
        child: Material(
          color: Colors.transparent,
          shape: CircleBorder(
            side: BorderSide(color: widget.iconColor, width: 1.2),
          ),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: widget.onPressed,
            child: Icon(Icons.add, size: 18, color: widget.iconColor),
          ),
        ),
      ),
    );
  }
}

/// 表挿入用のマス目プレビュー（2026-09-27追加、ユーザー指示）。Notion等の
/// 表挿入UIを参考にした、左上原点でホバー中のマスまでを塗りつぶす縦横比選択。
/// マスをクリックした瞬間に`(rows, columns)`で確定する（別途「作成」ボタンは
/// 置かない）。
class _TableSizePicker extends StatefulWidget {
  const _TableSizePicker({
    required this.accentColor,
    required this.neutralColor,
  });

  final Color accentColor;
  final Color neutralColor;

  static const int maxRows = 8;
  static const int maxColumns = 6;

  @override
  State<_TableSizePicker> createState() => _TableSizePickerState();
}

class _TableSizePickerState extends State<_TableSizePicker> {
  int _hoverRow = 0;
  int _hoverColumn = 0;

  @override
  Widget build(BuildContext context) {
    const cellSize = 22.0;
    const cellGap = 3.0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var r = 0; r < _TableSizePicker.maxRows; r++)
          Padding(
            padding: const EdgeInsets.only(bottom: cellGap),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var c = 0; c < _TableSizePicker.maxColumns; c++)
                  Padding(
                    padding: const EdgeInsets.only(right: cellGap),
                    child: MouseRegion(
                      onEnter: (_) => setState(() {
                        _hoverRow = r;
                        _hoverColumn = c;
                      }),
                      child: GestureDetector(
                        onTap: () => Navigator.of(context).pop((r + 1, c + 1)),
                        child: Container(
                          width: cellSize,
                          height: cellSize,
                          decoration: BoxDecoration(
                            color: r <= _hoverRow && c <= _hoverColumn
                                ? widget.accentColor
                                : widget.neutralColor,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        Text(
          '${_hoverColumn + 1} × ${_hoverRow + 1}',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
        ),
      ],
    );
  }
}
