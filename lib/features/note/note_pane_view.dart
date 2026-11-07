import 'dart:async';
import 'dart:convert';
import 'dart:math' show Random;

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/gestures.dart' show kPrimaryButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';

import '../../l10n/strings.dart';
import '../../l10n/tutorial_content.dart';
import '../guide/tutorial/tutorial_controller.dart';
import '../guide/tutorial/tutorial_target.dart';
import '../../models/app_ui_style.dart';
import '../../models/app_user.dart';
import '../../models/note.dart';
import '../../models/note_op.dart';
import '../../providers/app_ui_style_provider.dart';
import '../../providers/home_shell_providers.dart';
import '../../providers/repository_providers.dart';
import '../../utils/attachment_upload.dart';
import '../../utils/auto_dismiss_banner.dart';
import '../../utils/forward_message.dart';
import '../../utils/note_export.dart';
import '../../utils/share_attachment.dart';
import '../chat/forward_target_dialog.dart';
import '../../utils/note_copy.dart';
import '../../utils/note_markdown_parsers.dart';
import '../../utils/note_paste.dart';
import '../../utils/note_transaction_codec.dart';
import '../../utils/platform_info.dart';
import '../../widgets/glass/glass_app_bar.dart';
import '../../widgets/glass/glass_bottom_sheet.dart';
import '../../widgets/glass/glass_dialog.dart';
import '../../theme/block/block_theme.dart';
import '../../theme/gekiga/gekiga_colors.dart';
import '../../widgets/gekiga/gekiga_badge.dart';
import '../../widgets/glass/glass_surface.dart';
import '../../widgets/media_preview_frame.dart'
    show GekigaStraightMonochromeBox;
import '../../widgets/interactive_swipe_back.dart';
import '../../widgets/swipe_gestures.dart';
import 'blocks/link_embed_block.dart';
import 'block_move_drag.dart';
import 'draw_canvas_view.dart';
import 'note_table_delete.dart';
import 'blocks/table_of_contents_block.dart';
import '../../widgets/confirm_download_dialog.dart';
import '../../widgets/dialog_keyboard_shortcuts.dart';
import '../../widgets/app_dialog.dart';

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
  // 選択範囲が殆ど視認出来ないほど薄くなる問題があった為、ライト/
  // ダークそれぞれで十分視認出来る濃さを個別に指定する。
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

/// 本文の1行の長さ（半角換算の文字数。全角は2字分）。この幅で折り返す（2026-11-06）。
const _kNoteLineChars = 77;

/// コンピューターの本文の左右の余白。左は、カーソル行の「+」ボタン
/// （26px＋8pxの隙間）が入る分を空ける。
const _kNoteDesktopSidePadding = 48.0;

/// [_ObsidianNoteColors]から`EditorStyle.textStyleConfiguration`を組み立てる
/// （2026-09-26変更、以前はダーク時のみ白へ上書きする`_kNoteDarkText
/// StyleConfiguration`固定値だったが、ライトも含めてObsidian風パレットに
/// 統一した）。
TextStyleConfiguration _noteTextStyleConfiguration(
  _ObsidianNoteColors colors, {
  String? fontFamily,
  List<String>? fontFamilyFallback,
}) {
  return TextStyleConfiguration(
    // フォントは設定の「フォントデザイン」（アプリ全体のテーマ）に従う。エディタは文字の
    // スタイルをテーマから継承しない為、ここで明示する（2026-11-06）。
    text: TextStyle(
      fontSize: 16,
      color: colors.text,
      fontFamily: fontFamily,
      fontFamilyFallback: fontFamilyFallback,
    ),
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
/// ノートの題名の最大文字数（見た目の1文字単位）。
const kMaxNoteTitleLength = 100;

class NotePaneView extends ConsumerStatefulWidget {
  const NotePaneView({
    required this.isDm,
    required this.conversationId,
    required this.roomId,
    required this.noteId,
    required this.currentUser,
    required this.onClose,
    this.popupWidth,
    super.key,
  });

  final bool isDm;
  final String conversationId;
  final String roomId;
  final String noteId;
  final AppUser currentUser;
  final VoidCallback onClose;

  /// 開いているポップアップの幅を、本文の幅（半角77字）に合わせて知らせる先
  /// （`showAlbumDetailPopup`の`widthOverride`）。ドローは知らせない（既定の広さ）。
  final ValueNotifier<double?>? popupWidth;

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
  /// false。種別は作成時に固定され、後から切り替わることは無い。
  bool _isDraw = false;
  bool _noteLoaded = false;

  /// 開いているノートの作成者（削除ボタンを出すかの判定用、2026-11-07）。
  String? _createdBy;

  // dispose中は`ref`が使えない（Riverpod 3は例外を投げる）ので、閉じる時の保存に使う
  // リポジトリは先に保持しておく。
  late final _noteRepository = ref.read(noteRepositoryProvider);

  /// 保存済みの（一覧に出ている）題名。題名は閉じた時（[_close]・[dispose]）に確定し、
  /// それまでの途中保存は[_savedTitle]のまま書く。空欄で閉じた時も元の題名に戻す
  /// （2026-11-07）。
  String _savedTitle = '';

  /// 題名を編集したが、まだ確定（保存）していないか。
  bool _titleEdited = false;

  /// 保存する題名。[closing]（閉じる時）は入力欄の値で、空欄（空白のみ）なら元の題名。
  /// 途中の保存は題名を変えない。
  String _titleFor({required bool closing}) {
    if (!closing) return _savedTitle;
    final text = _titleController.text;
    return text.trim().isEmpty ? _savedTitle : text;
  }

  /// 閉じる時の保存が済んだ題名を、保存済みとして記録する。
  void _markTitleCommitted(String title) {
    _savedTitle = title;
    _titleEdited = false;
  }

  /// 閲覧モード（読み取り専用）か。開いた時は編集モード（2026-11-06）。
  bool _readOnly = false;

  /// 閲覧・編集の選択を端末に保存するキー（ノートごとではなく共通、2026-11-06）。
  static const _readOnlyPrefsKey = 'noteReadOnly';

  Future<void> _restoreReadOnly() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getBool(_readOnlyPrefsKey) ?? false;
    if (!mounted || saved == _readOnly) return;
    setState(() => _readOnly = saved);
    final editorState = _editorState;
    if (editorState != null) {
      editorState.editable = !saved;
      if (saved) editorState.selection = null;
    }
  }

  void _toggleReadOnly() {
    setState(() => _readOnly = !_readOnly);
    SharedPreferences.getInstance().then(
      (prefs) => prefs.setBool(_readOnlyPrefsKey, _readOnly),
    );
    final editorState = _editorState;
    if (editorState != null) {
      editorState.editable = !_readOnly;
      // 閲覧モードに入る時は、カーソル・選択を外す。
      if (_readOnly) editorState.selection = null;
    }
  }

  EditorScrollController? _scrollController;
  final _titleController = TextEditingController();
  final _titleFocusNode = FocusNode();

  /// ページ全体のフォーカス（Escで閉じるキー処理の受け口）。
  final _pageFocusNode = FocusNode(debugLabel: 'NotePage');
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
    _noteRepository;
    WidgetsBinding.instance.addObserver(this);
    // 重ねて開いた直後に、ページがEscを受け取れるようフォーカスを取る
    // （`autofocus`は他にフォーカスがあると効かない）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_pageFocusNode.hasFocus) _pageFocusNode.requestFocus();
    });
    _titleFocusNode.addListener(
      () => _debugCaret('title focus=${_titleFocusNode.hasFocus}'),
    );
    _load();
    _restoreReadOnly();
  }

  /// 直前のカーソルの位置。目次ブロックにカーソルが乗った時、移動方向
  /// （↑↓）を判定して隣の行へ逃がすのに使う。
  Path? _lastSelectionPath;

  void _onSelectionChanged() {
    final editorState = _editorState;
    final selection = editorState?.selection;
    if (editorState != null && selection != null) {
      moveCaretOffTableOfContents(editorState, _lastSelectionPath);
    }
    _lastSelectionPath = editorState?.selection?.end.path;
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
    // このノートを開いている間、操作ログのエコー判定に使うランダムなID。
    // 以前はFirestoreの自動採番IDをローカルで作っていたが、Firebaseに依存しない
    // 乱数にした（練習用の画面・テストでFirebaseを初期化せずに開けるように）。
    _sessionId =
        '${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(0xFFFFFFFF)}';
    final noteRepository = ref.read(noteRepositoryProvider);
    final note = await noteRepository.getNote(
      isDm: widget.isDm,
      conversationId: widget.conversationId,
      roomId: widget.roomId,
      noteId: widget.noteId,
    );
    if (!mounted) return;
    _titleController.text = note?.title ?? '';
    _createdBy = note?.createdBy;
    _savedTitle = note?.title ?? '';
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

  /// 使い方ガイドの実行中だけ、書かれた内容に応じて「出来事」を知らせる（見出し・リスト・
  /// 太字・表などが出来たら次の手順へ進める）。普段（ガイドなし）は何もしない。
  void _notifyTutorialOfDocument() {
    if (!mounted || ref.read(tutorialControllerProvider) == null) return;
    final editorState = _editorState;
    if (editorState == null) return;
    final found = <String>{};
    void visit(Node node) {
      switch (node.type) {
        case HeadingBlockKeys.type:
          found.add('note-heading');
        case BulletedListBlockKeys.type:
          found.add('note-bulleted');
        case NumberedListBlockKeys.type:
          found.add('note-numbered');
        case TableBlockKeys.type ||
            DividerBlockKeys.type ||
            ImageBlockKeys.type ||
            TableOfContentsBlockKeys.type ||
            LinkEmbedBlockKeys.type:
          found.add('note-inserted');
      }
      final delta = node.delta;
      if (delta != null &&
          delta.any(
            (op) => op is TextInsert && op.attributes?['bold'] == true,
          )) {
        found.add('note-bold');
      }
      node.children.forEach(visit);
    }

    visit(editorState.document.root);
    final controller = ref.read(tutorialControllerProvider.notifier);
    for (final event in found) {
      controller.notify(event);
    }
  }

  void _handleLocalTransaction(EditorTransactionValue event) {
    final (time, transaction, _) = event;
    if (time != TransactionTime.after) return;
    _notifyTutorialOfDocument();
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
  /// より前は、このチェックポイントの内容に反映済み」という前提に依る為、
  /// ここでのチェックポイント保存は`_dirty`の有無に関わらず常に行う（他人の
  /// 編集を受信しただけで自分は未編集の場合でも、間引き前には必ず最新の
  /// マージ済み内容を書き込む）。
  Future<void> _checkpointAndPrune({bool closing = false}) async {
    _checkpointDebounce?.cancel();
    final editorState = _editorState;
    final title = _titleFor(closing: closing);
    if (_isDraw) {
      // ドローノートはタイトルだけを保存する（本文`content`は空のまま）。
      if (!_dirty && !(closing && _titleEdited)) return;
      _dirty = false;
      if (closing) _markTitleCommitted(title);
      await ref
          .read(noteRepositoryProvider)
          .updateNote(
            isDm: widget.isDm,
            conversationId: widget.conversationId,
            roomId: widget.roomId,
            noteId: widget.noteId,
            title: title,
            content: const {},
            editedBy: widget.currentUser.userId,
          );
      return;
    }
    if (editorState == null) return;
    _dirty = false;
    if (closing) _markTitleCommitted(title);
    final noteRepository = ref.read(noteRepositoryProvider);
    final watermark = _lastAppliedOpCreatedAt;
    await noteRepository.updateNote(
      isDm: widget.isDm,
      conversationId: widget.conversationId,
      roomId: widget.roomId,
      noteId: widget.noteId,
      title: title,
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

  void _handleTitleChanged(String _) {
    _titleEdited = true;
    _scheduleCheckpoint();
  }

  /// 開いているノート（マークダウン・ドロー）自体を削除する（作成者のみ、確認あり）。
  /// ノート一覧の削除アイコン（`note_popup_content.dart`）と同じ文言・処理で、削除できたら
  /// このペインを閉じる（2026-11-07）。削除するノートへ保存し直さないよう、未送信の
  /// 編集・保存の予約は捨てる。
  Future<void> _deleteNote() async {
    final strings = ref.read(appStringsProvider);
    final isGlass = ref.read(appUiStyleProvider) == AppUiStyle.glass;
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final title = Text(strings.noteDeleteConfirmTitle);
        final content = Text(strings.calendarDeleteConfirmMessage);
        final actions = [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
            ),
            child: Text(strings.delete),
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
    if (confirmed != true || !mounted) return;
    _checkpointDebounce?.cancel();
    _checkpointTimer?.cancel();
    _sendDebounce?.cancel();
    _dirty = false;
    _titleEdited = false;
    try {
      await ref
          .read(noteRepositoryProvider)
          .deleteNote(
            isDm: widget.isDm,
            conversationId: widget.conversationId,
            roomId: widget.roomId,
            noteId: widget.noteId,
          );
      if (mounted) widget.onClose();
    } catch (e) {
      if (mounted) showAutoDismissBanner(context, message: '$e');
    }
  }

  Future<void> _close() async {
    _sendDebounce?.cancel();
    await _flushOutgoing();
    await _checkpointAndPrune(closing: true);
    if (mounted) widget.onClose();
  }

  @override
  void dispose() {
    _checkpointDebounce?.cancel();
    _checkpointTimer?.cancel();
    _sendDebounce?.cancel();
    // dispose中は非同期await不可の為、確定済みの内容をfire-and-forgetで
    // 保存する（ページを閉じる通常経路は`_close`が先にawait済みの為、
    // ここに到達するのは想定外の破棄経路への保険）。次にこのノートを開いた
    // クライアントが追いつき処理の一環で操作ログの間引きも行うため、ここでは
    // 間引きまでは行わない。
    final editorState = _editorState;
    if ((_dirty || _titleEdited) && _isDraw) {
      _noteRepository.updateNote(
        isDm: widget.isDm,
        conversationId: widget.conversationId,
        roomId: widget.roomId,
        noteId: widget.noteId,
        title: _titleFor(closing: true),
        content: const {},
        editedBy: widget.currentUser.userId,
      );
    } else if ((_dirty || _titleEdited) && editorState != null) {
      _noteRepository.updateNote(
        isDm: widget.isDm,
        conversationId: widget.conversationId,
        roomId: widget.roomId,
        noteId: widget.noteId,
        title: _titleFor(closing: true),
        content: editorState.document.toJson(),
        editedBy: widget.currentUser.userId,
      );
    }
    if (_pendingOutgoingTransactions.isNotEmpty) {
      _noteRepository.appendNoteOp(
        isDm: widget.isDm,
        conversationId: widget.conversationId,
        roomId: widget.roomId,
        noteId: widget.noteId,
        transactions: _pendingOutgoingTransactions,
        sessionId: _sessionId,
        authorId: widget.currentUser.userId,
      );
    }
    _pageFocusNode.dispose();
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
  /// `build`の外（`IconButton.onPressed`）の為、同じ配色計算を単独で
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
  /// 提供する。`appflowy_editor`の「/」メニューはモバイル不可の為、各項目の
  /// `handler`は`menuService`を使わない実装であることを利用し、PC用の
  /// `SelectionMenu`オーバーレイを介さず直接呼ぶ（`SelectionMenu`は
  /// `SelectionMenuService`を満たす値として渡すだけで`show()`は呼ばない）。
  /// 書式（太字等）は同日に廃止した「T」ボタンのボトムシートから、
  /// テキスト選択時のポップアップ（[_buildMobileSelectionToolbar]）へ移した。
  Future<void> _openInsertBottomSheet() async {
    final editorState = _editorState;
    if (editorState == null) return;
    ref.read(tutorialControllerProvider.notifier).notify('note-insert-menu');
    final isGlass = ref.read(appUiStyleProvider) == AppUiStyle.glass;
    final strings = ref.read(appStringsProvider);
    // 「/」入力の後始末（直前の文字を消す処理）は挿入メニューを開いた
    // 経緯に依存する為、AppBarから開くここでは無効にする。PCの「+」が
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
                      if (!_readOnly)
                        textAction(strings.noteSelectionCut, cutCommand),
                      textAction(strings.noteSelectionCopy, noteCopyCommand),
                      if (!_readOnly)
                        textAction(
                          strings.noteSelectionPaste,
                          notePasteCommand,
                        ),
                      if (!_readOnly)
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
      // 区切り線: ライブラリ標準の`dividerMenuItem`は表示名が英語固定
      // （`AppFlowyEditorL10n`）の為、挿入処理は同じまま`strings`で名前を
      // 出す専用の項目にした。
      SelectionMenuItem(
        getName: () => strings.noteMenuDivider,
        icon: (editorState, isSelected, style) => Icon(
          Icons.horizontal_rule,
          size: 18.0,
          color: isSelected
              ? style.selectionMenuItemSelectedIconColor
              : style.selectionMenuItemIconColor,
        ),
        keywords: const ['horizontal rule', 'divider'],
        handler: (editorState, _, _) => _insertDivider(editorState),
      ),
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
            insertTableOfContentsAfterSelection(editorState),
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
    final url = await showAppDialog<String>(
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
    final size = await showAppDialog<(int, int)>(
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

  /// 区切り線を挿入し、直後の空の段落へカーソルを置く（`dividerMenuItem`と
  /// 同じ処理。空の段落の上で実行した時はその段落を置き換える）。
  void _insertDivider(EditorState editorState) {
    final selection = editorState.selection;
    if (selection == null || !selection.isCollapsed) return;
    final path = selection.end.path;
    final delta = editorState.getNodeAtPath(path)?.delta;
    if (delta == null) return;
    final insertedPath = delta.isEmpty ? path : path.next;
    final transaction = editorState.transaction
      ..insertNode(insertedPath, dividerNode())
      ..insertNode(insertedPath, paragraphNode())
      ..afterSelection = Selection.collapsed(Position(path: insertedPath.next));
    editorState.apply(transaction);
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
        // しない為、ファイル名をリンク（href=Storage URL）にした段落として
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
  /// ノート（マークダウンは`.md`、ドローは白背景の`.png`）を、保存・共有・転送用のバイト列にする。
  /// 書き出せない時（ドローが空など）はバナーを出してnull。
  Future<({String fileName, Uint8List bytes, String mimeType})?>
  _buildExport() async {
    final strings = ref.read(appStringsProvider);
    final baseName = sanitizeFileName(
      _titleController.text,
      strings.noteDownloadDefaultName,
    );
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
      if (!mounted) return null;
      if (png == null) {
        showAutoDismissBanner(
          context,
          message: strings.noteDrawNothingToExport,
        );
        return null;
      }
      return (fileName: '$baseName.png', bytes: png, mimeType: 'image/png');
    }
    final editorState = _editorState;
    if (editorState == null) return null;
    final markdown = documentToMarkdown(
      editorState.document,
      customParsers: noteMarkdownCustomParsers,
    );
    return (
      fileName: '$baseName.md',
      bytes: Uint8List.fromList(utf8.encode(markdown)),
      mimeType: 'text/markdown',
    );
  }

  Future<void> _download() async {
    final strings = ref.read(appStringsProvider);
    final baseName = sanitizeFileName(
      _titleController.text,
      strings.noteDownloadDefaultName,
    );
    if (!await confirmDownload(
      context,
      ref,
      fileName: '$baseName.${_isDraw ? 'png' : 'md'}',
    )) {
      return;
    }
    if (!mounted) return;
    try {
      final file = await _buildExport();
      if (file == null) return;
      await saveNoteFile(
        fileName: file.fileName,
        bytes: file.bytes,
        mimeType: file.mimeType,
      );
    } catch (e) {
      debugPrint('[note-download] failed: $e');
      if (mounted) {
        showAutoDismissBanner(context, message: strings.noteDownloadFailed);
      }
    }
  }

  /// ノートのファイル（`.md`／ドローは`.png`）をOSの共有シートへ渡す（2026-11-06）。共有シートが
  /// 使えない環境（Linux等）では、ダウンロードと同じ保存にする。
  Future<void> _share() async {
    final strings = ref.read(appStringsProvider);
    try {
      final file = await _buildExport();
      if (file == null) return;
      final shared = await shareBytesFile(
        bytes: file.bytes,
        name: file.fileName,
        mimeType: file.mimeType,
      );
      if (!shared) {
        await saveNoteFile(
          fileName: file.fileName,
          bytes: file.bytes,
          mimeType: file.mimeType,
        );
      }
    } catch (e) {
      debugPrint('[note-share] failed: $e');
      if (mounted) {
        showAutoDismissBanner(context, message: strings.noteDownloadFailed);
      }
    }
  }

  /// ノートのファイルを、選んだ一対・広場の寄合へ添付として送る（2026-11-06、`.md`で送る）。
  Future<void> _forward() async {
    final strings = ref.read(appStringsProvider);
    try {
      final file = await _buildExport();
      if (file == null || !mounted) return;
      final target = await showForwardTargetDialog(
        context,
        currentUserId: widget.currentUser.userId,
        preview: ForwardPreview(files: [file.fileName]),
      );
      if (target == null || !mounted) return;
      showAutoDismissBanner(context, message: strings.forwardSending);
      await forwardBytes(
        ref: ref,
        bytes: file.bytes,
        fileName: file.fileName,
        contentType: 'file',
        target: target,
        senderId: widget.currentUser.userId,
        senderRhingSeed: widget.currentUser.rhingSeed,
      );
      if (mounted) {
        showAutoDismissBanner(context, message: strings.forwardDone);
      }
    } catch (e, st) {
      debugPrint('[note-forward] failed: $e\n$st');
      if (mounted) {
        showAutoDismissBanner(context, message: strings.forwardFailed);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 語らいタブ以外（身だしなみ・設定）に切り替わった際、選択中のまま残った
    // `FloatingToolbar`が最前面に描画され続ける不具合の修正（2026-09-27
    // 追加、ユーザー指示）。`HomeScreen`は3タブとも`IndexedStack`で常時
    // マウントし続ける為、`NotePaneView`自体は破棄されず選択も維持され、
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

    final titleField = TextField(
      controller: _titleController,
      focusNode: _titleFocusNode,
      // 閲覧モードでは題名も読み取り専用。
      readOnly: _readOnly,
      // 題名の文字数の上限（2026-11-06）。既に超えている題名は切らず、それ以上は足せない。
      maxLength: kMaxNoteTitleLength,
      maxLengthEnforcement: MaxLengthEnforcement.enforced,
      onChanged: _handleTitleChanged,
      style: Theme.of(context).textTheme.titleMedium,
      decoration: InputDecoration(
        hintText: strings.noteTitleFieldHint,
        // 版画のテーマは入力欄に太枠（`enabledBorder`/`focusedBorder`）を付ける為、`border`だけでは
        // 消えず、ポップアップの枠との間に隙間のある題名の枠が出ていた。全状態で枠・塗りを消し、
        // 題名はポップアップの左端から始める（2026-11-06）。
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        disabledBorder: InputBorder.none,
        filled: false,
        counterText: '',
        isCollapsed: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
      ),
    );
    final downloadAction = IconButton(
      icon: const Icon(Icons.download),
      tooltip: '',
      onPressed: !_noteLoaded ? null : _download,
    );
    // モバイル専用の挿入ボタン（2026-10-04追加、ユーザー指示）。PCの「+」
    // /「/」メニューが使えない為、AppBarからボトムシートで同じ項目を開く
    // （`_openInsertBottomSheet`参照）。書式は選択時ポップアップへ移した。
    final insertAction = IconButton(
      icon: const Icon(Icons.add),
      tooltip: strings.noteInsertTooltip,
      onPressed: _editorState == null ? null : () => _openInsertBottomSheet(),
    );
    // 閲覧・編集モードの切り替え（Obsidianと同じく、押すと切り替わる先のモードの絵）。
    // 転送ボタンの左隣。ドローは対象外（2026-11-06）。
    final modeAction = IconButton(
      icon: Icon(_readOnly ? Icons.edit_outlined : Icons.menu_book_outlined),
      tooltip: '',
      onPressed: !_noteLoaded ? null : _toggleReadOnly,
    );
    final forwardAction = IconButton(
      icon: const Icon(Icons.forward_outlined),
      tooltip: '',
      onPressed: !_noteLoaded ? null : _forward,
    );
    final shareAction = IconButton(
      icon: const Icon(Icons.share_outlined),
      tooltip: '',
      onPressed: !_noteLoaded ? null : _share,
    );
    // 削除は作成者だけ（firestore.rulesの作成者限定削除と同じ）。
    final canDelete = _noteLoaded && _createdBy == widget.currentUser.userId;
    final deleteAction = IconButton(
      icon: const Icon(Icons.delete_outline),
      tooltip: '',
      onPressed: _deleteNote,
    );

    // タイトル欄（appBar側の`titleField`）にフォーカスがある間にEscを押した
    // 場合も閉じられるよう、`Scaffold.body`だけでなく`appBar`も含めて
    // `Focus`で包む（appBarとbodyはフォーカスツリー上兄弟の為、body側だけ
    // 包んでもタイトル欄フォーカス中はこのハンドラの祖先チェーンに入らない、
    // 2026-09-07変更）。
    final page = Focus(
      focusNode: _pageFocusNode,
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.escape) {
          _close();
          return KeyEventResult.handled;
        }
        // 閲覧モードのBackspaceは何もしない（2026-11-06）。入力欄にフォーカスが無いと、
        // Flutterが処理しない（`handled`にしない）キーはブラウザへ渡り、ブラウザの
        // 「戻る」になってポップアップが閉じていた。`handled`で止める。
        if (_readOnly && event.logicalKey == LogicalKeyboardKey.backspace) {
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Scaffold(
        backgroundColor: noteColors.background,
        appBar: isGlass
            ? GlassAppBar(
                // 戻る矢印は出さない（ダイアログで開くため。閉じるのはEsc・暗幕・戻る操作、
                // 2026-11-05、ユーザー指示）。
                automaticallyImplyLeading: false,
                title: titleField,
                actions: [
                  if (isMobile && !_isDraw && !_readOnly) insertAction,
                  if (!_isDraw) modeAction,
                  forwardAction,
                  shareAction,
                  downloadAction,
                  if (canDelete) deleteAction,
                ],
              )
            : AppBar(
                backgroundColor: noteColors.background,
                foregroundColor: noteColors.text,
                automaticallyImplyLeading: false,
                title: titleField,
                actions: [
                  if (isMobile && !_isDraw && !_readOnly) insertAction,
                  if (!_isDraw) modeAction,
                  forwardAction,
                  shareAction,
                  downloadAction,
                  if (canDelete) deleteAction,
                ],
              ),
        // 下スワイプで閉じる（既存）。右スワイプは画面全体（AppBar込み）を
        // `InteractiveSwipeBackTransition`で包む（下の`return`参照）。
        body: SwipeDownToDismiss(
          onDismiss: _close,
          // ドローノートはEscと暗幕・戻る操作でしか閉じない（2026-10-10、ユーザー指示。矢印は2026-11-05に削除。
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
              : TutorialTarget(
                  id: TutorialTargetIds.noteEditor,
                  child: _withStats(
                    _buildEditorBody(strings, noteColors, isMobile),
                    strings,
                    noteColors,
                  ),
                ),
        ),
      ),
    );
    // 右スワイプで閉じる操作は、設定・身だしなみ・チャットと同じ指追従の
    // `InteractiveSwipeBackTransition`（2026-10-07、以前は離散的な
    // `SwipeBackDetector`でアニメーションが無かった）。モバイルのみ・ドロー
    // 以外（ペンの横ストロークで誤って閉じる為）・カーソル（選択）が無い間
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
      // 空白・キャンバスのタップでフォーカスがどこにも無くなっても、Escで戻れるよう
      // タップ後にページのフォーカスを取り直す（入力欄等が取った場合は奪わない）。
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_pageFocusNode.hasFocus) {
            _pageFocusNode.requestFocus();
          }
        }),
        child: _isDraw ? HorizontalDragAbsorber(child: page) : page,
      ),
    );
  }

  /// エディタの右下に文字数（選択中は、その左隣に選択した文字数）を重ねる（2026-11-06、
  /// Obsidianのステータスバー風）。タップは下のエディタへ通す。
  Widget _withStats(
    Widget editor,
    Strings strings,
    _ObsidianNoteColors noteColors,
  ) {
    final editorState = _editorState;
    if (editorState == null) return editor;
    return Stack(
      children: [
        Positioned.fill(child: editor),
        Positioned(
          right: 16,
          bottom: 6,
          child: IgnorePointer(
            child: _NoteStats(
              editorState: editorState,
              color: noteColors.mutedText,
              background: noteColors.background,
              selectedPrefix: strings.noteSelectedPrefix,
              unit: strings.noteCharsUnit,
            ),
          ),
        ),
      ],
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
    final themeFont = Theme.of(context).textTheme.bodyLarge;
    final textStyleConfiguration = _noteTextStyleConfiguration(
      noteColors,
      fontFamily: themeFont?.fontFamily,
      fontFamilyFallback: themeFont?.fontFamilyFallback,
    );
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
    // 題名と本文の間に余白を空ける（2026-11-06、ユーザー指示）。左右の余白は既定のまま、
    // 上だけ足す（「+」ボタン等の位置計算は`padding.left`だけを使うので影響しない）。
    // 本文のカーソルはアプリのアクセントカラー（ノート独自の紫ではなく、2026-11-06）。
    final cursorColor = Theme.of(context).colorScheme.primary;
    // 範囲選択のハイライト（「ラベル」）もアクセントカラー。背景が暗くても見える濃さにする。
    final selectionColor = cursorColor.withValues(alpha: 0.4);
    final editorStyle = isMobile
        ? EditorStyle.mobile(
            textStyleConfiguration: textStyleConfiguration,
            cursorColor: cursorColor,
            selectionColor: selectionColor,
          )
        : EditorStyle.desktop(
            textStyleConfiguration: textStyleConfiguration,
            cursorColor: cursorColor,
            selectionColor: selectionColor,
          );
    // 本文は半角77字の幅で折り返す（Obsidianの「読みやすい行の長さ」のように、本文の範囲を
    // 決める）。ポップアップの幅も、この範囲＋左右の余白に合わせる（`popupWidth`）。
    // 半角1字の幅は数字「0」で測る（文字サイズ・フォント・拡大率に追従）。全角は2字分になる。
    final bodyTextStyle = Theme.of(
      context,
    ).textTheme.bodyLarge!.merge(textStyleConfiguration.text);
    final textColumnWidth = (TextPainter(
      text: TextSpan(text: '0' * _kNoteLineChars, style: bodyTextStyle),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout()).width;
    final sidePadding = isMobile ? 20.0 : _kNoteDesktopSidePadding;
    final popupWidthWanted = textColumnWidth + sidePadding * 2;
    final popupWidth = widget.popupWidth;
    if (popupWidth != null && popupWidth.value != popupWidthWanted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) popupWidth.value = popupWidthWanted;
      });
    }
    final editor = AppFlowyEditor(
      editorState: editorState,
      editorScrollController: scrollController,
      // モバイル判定のWeb版は、appflowy_editorがisDesktopOrWebでデスクトップ用の
      // 選択処理を使い、指を置いた瞬間にカーソル・ドラッグ選択が作られて右スワイプ
      // で閉じる操作（`SwipeBackDetector`）が負けていた（2026-10-07修正）。
      // モバイルのみ押下即時のドラッグ選択を切り、水平スワイプを先に勝たせる。
      enablePanImmediate: !isMobile,
      // 閲覧モードでは編集不可（再構築のたびに`editorState.editable`が上書きされる為、
      // ウィジェットの引数で渡す。2026-11-06）。
      editable: !_readOnly,
      editorStyle: editorStyle.copyWith(
        padding: EdgeInsets.fromLTRB(
          sidePadding,
          editorStyle.padding.top + 24,
          sidePadding,
          editorStyle.padding.bottom,
        ),
        // エディタは`MediaQuery`の文字の拡大率を見ず、独自の`textScaleFactor`（既定1.0）だけを
        // 使う。設定のフォントサイズ（アプリ全体の拡大率）が効くよう、ここで渡す（2026-11-06）。
        textScaleFactor: MediaQuery.textScalerOf(context).scale(1),
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
      // 閲覧モードはコピーと全選択だけ（切り取り・貼り付け・削除・改行などを無効にする）。
      commandShortcutEvents: _readOnly
          ? [noteCopyCommand, selectAllCommand]
          : [
              wholeTableBackspaceCommand,
              wholeTableDeleteCommand,
              ...standardCommandShortcutEvents.where(
                (e) =>
                    e != exitEditingCommand &&
                    e != pasteCommand &&
                    e != copyCommand,
              ),
              noteCopyCommand,
              notePasteCommand,
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
          // 押した時点でメニューを「+」の右下に開く（押したまま項目へなぞって離すと選べる、
          // 2026-11-06）。
          onPressed: (buttonRect) {
            ref
                .read(tutorialControllerProvider.notifier)
                .notify('note-insert-menu');
            final ui = ref.read(appUiStyleProvider);
            final menuTheme = Theme.of(context);
            final menuStyle = _insertMenuStyle(menuTheme, ui);
            SelectionMenu(
              context: context,
              editorState: editorState,
              selectionMenuItems: _buildSelectionMenuItems(strings),
              deleteSlashByDefault: false,
              anchorRect: buttonRect,
              style: menuStyle,
              surfaceBuilder: _insertMenuSurface(menuTheme, ui, menuStyle),
            ).show();
          },
        ),
      ],
    );
  }
}

/// 挿入メニュー（「+」・「/」）の色を、UIスタイルに合わせる（2026-11-06）。アイコン・文字・
/// 選択中の項目の色。他の項目（リンク入力など）の色は標準のまま。
SelectionMenuStyle _insertMenuStyle(ThemeData theme, AppUiStyle ui) {
  final base = theme.brightness == Brightness.dark
      ? SelectionMenuStyle.dark
      : SelectionMenuStyle.light;
  final scheme = theme.colorScheme;
  final Color bg, text, selectedBg, selectedText;
  switch (ui) {
    case AppUiStyle.gekiga:
      bg = GekigaColors.panel;
      text = GekigaColors.onPanel;
      selectedBg = GekigaColors.onPanel;
      selectedText = GekigaColors.panel;
    case AppUiStyle.glass:
      bg = Colors.transparent;
      text = scheme.onSurface;
      selectedBg = scheme.primary.withValues(alpha: 0.45);
      selectedText = scheme.onSurface;
    case AppUiStyle.block:
    case AppUiStyle.flat:
      bg = theme.brightness == Brightness.light && ui == AppUiStyle.block
          ? Colors.white
          : scheme.surface;
      text = scheme.onSurface;
      selectedBg = scheme.primary;
      selectedText = scheme.onPrimary;
  }
  return SelectionMenuStyle(
    selectionMenuBackgroundColor: bg,
    selectionMenuItemTextColor: text,
    selectionMenuItemIconColor: text,
    selectionMenuItemSelectedTextColor: selectedText,
    selectionMenuItemSelectedIconColor: selectedText,
    selectionMenuItemSelectedColor: selectedBg,
    selectionMenuUnselectedLabelColor: text,
    selectionMenuDividerColor: base.selectionMenuDividerColor,
    selectionMenuLinkBorderColor: base.selectionMenuLinkBorderColor,
    selectionMenuInvalidLinkColor: base.selectionMenuInvalidLinkColor,
    selectionMenuButtonColor: base.selectionMenuButtonColor,
    selectionMenuButtonTextColor: base.selectionMenuButtonTextColor,
    selectionMenuButtonIconColor: base.selectionMenuButtonIconColor,
    selectionMenuButtonBorderColor: base.selectionMenuButtonBorderColor,
    selectionMenuTabIndicatorColor: base.selectionMenuTabIndicatorColor,
  );
}

/// 挿入メニューの面（背景・枠）を、UIスタイルに合わせる（2026-11-06）。影は版画だけ
/// （硬い影、CLAUDE.mdの例外）。
Widget Function(Widget child) _insertMenuSurface(
  ThemeData theme,
  AppUiStyle ui,
  SelectionMenuStyle style,
) {
  final radius = BorderRadius.circular(12);
  return (child) {
    switch (ui) {
      case AppUiStyle.gekiga:
        // 地色が黒（isMe: false）の箱。メニューの文字は白、選択中は白地に黒文字。
        return GekigaStraightMonochromeBox(isMe: false, child: child);
      case AppUiStyle.glass:
        return GlassSurface(
          variant: GlassVariant.floating,
          borderRadius: radius,
          child: ClipRRect(borderRadius: radius, child: child),
        );
      case AppUiStyle.block:
        return Builder(
          builder: (context) => Theme(
            data: theme,
            child: Builder(
              builder: (context) => blockMaterialBox(
                context,
                color: style.selectionMenuBackgroundColor,
                child: child,
              ),
            ),
          ),
        );
      case AppUiStyle.flat:
        return Material(
          color: style.selectionMenuBackgroundColor,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
          child: child,
        );
    }
  };
}

/// PC専用、カーソルが乗っている行の右端に追従する「+」ボタン
/// （2026-09-27追加、ユーザー指示）。`editorState.selectionRects()`
/// （`FloatingToolbar`が自身の位置決めに使うのと同じ公開API）でカーソルの
/// 矩形（グローバル座標）を取得し、[stackKey]が指す`Stack`のローカル座標へ
/// 変換して`Positioned`で重ねる。選択がcollapsed（カーソルのみ、ドラッグ
/// 選択中でない）の間だけ表示する。
class _CursorLineAddButton extends ConsumerStatefulWidget {
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
  final void Function(Rect buttonRect) onPressed;

  @override
  ConsumerState<_CursorLineAddButton> createState() =>
      _CursorLineAddButtonState();
}

class _CursorLineAddButtonState extends ConsumerState<_CursorLineAddButton> {
  Rect? _cursorRect;
  final _buttonKey = GlobalKey();

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

  /// 「+」の見た目をUIスタイルに合わせる（2026-11-06）。
  Widget _plusFace(BuildContext context, double size) {
    final ui = ref.watch(appUiStyleProvider);
    final scheme = Theme.of(context).colorScheme;
    switch (ui) {
      case AppUiStyle.gekiga:
        return GekigaBadgeShape(
          color: GekigaColors.panel,
          seed: 7,
          child: const Icon(Icons.add, size: 18, color: GekigaColors.onPanel),
        );
      case AppUiStyle.glass:
        return GlassSurface(
          variant: GlassVariant.card,
          opaque: true,
          borderRadius: BorderRadius.circular(size / 2),
          child: Center(
            child: Icon(Icons.add, size: 18, color: scheme.onSurface),
          ),
        );
      case AppUiStyle.block:
        return blockMaterialBox(
          context,
          radius: size / 2,
          shadowOffset: const Offset(2, 2),
          color: Theme.of(context).brightness == Brightness.light
              ? Colors.white
              : scheme.surface,
          child: Center(
            child: Icon(Icons.add, size: 18, color: scheme.onSurface),
          ),
        );
      case AppUiStyle.flat:
        return Material(
          color: scheme.primary,
          shape: const CircleBorder(),
          child: Icon(Icons.add, size: 18, color: scheme.onPrimary),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    // 閲覧モード（読み取り専用）では出さない。
    if (!widget.editorState.editable) return const SizedBox.shrink();
    final rect = _cursorRect;
    if (rect == null) return const SizedBox.shrink();
    const buttonSize = 26.0;
    const gapFromText = 8.0;
    // 本文が実際に始まる位置（エディタの左余白）のすぐ手前にボタンが来る
    // よう、固定の8pxではなくエディタ自身の左パディングから逆算する
    // （2026-09-27修正、デスクトップは既定で左右100pxの余白がある為）。
    final left =
        (widget.editorState.editorStyle.padding.left - buttonSize - gapFromText)
            .clamp(0.0, double.infinity);
    return Positioned(
      top: rect.top + (rect.height - buttonSize) / 2,
      left: left,
      // 押した瞬間にメニューを開き、押したまま項目へなぞって離すとその項目を選ぶ
      // （離した所が項目の外ならメニューは開いたまま。`SelectionMenuPointerTracker`参照）。
      child: Listener(
        onPointerDown: (event) {
          if (event.buttons != kPrimaryButton) return;
          final box = _buttonKey.currentContext?.findRenderObject();
          if (box is! RenderBox || !box.attached) return;
          widget.onPressed(box.localToGlobal(Offset.zero) & box.size);
        },
        onPointerMove: (event) =>
            SelectionMenuPointerTracker.move(event.position),
        onPointerUp: (event) =>
            SelectionMenuPointerTracker.release(event.position),
        onPointerCancel: (_) => SelectionMenuPointerTracker.cancel(),
        child: SizedBox(
          key: _buttonKey,
          width: buttonSize,
          height: buttonSize,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: _plusFace(context, buttonSize),
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

/// エディタの文字数表示（2026-11-06）。本文の全文字数（改行は数えない）と、選択中はその左隣に
/// 選択した文字数。文書の変更・選択の変化のたびに数え直す。
class _NoteStats extends StatefulWidget {
  const _NoteStats({
    required this.editorState,
    required this.color,
    required this.background,
    required this.selectedPrefix,
    required this.unit,
  });

  final EditorState editorState;
  final Color color;
  final Color background;
  final String selectedPrefix;
  final String unit;

  @override
  State<_NoteStats> createState() => _NoteStatsState();
}

class _NoteStatsState extends State<_NoteStats> {
  int _total = 0;
  int _selected = 0;
  StreamSubscription<dynamic>? _subscription;

  @override
  void initState() {
    super.initState();
    _recount();
    _subscription = widget.editorState.transactionStream.listen(
      (_) => _recount(),
    );
    widget.editorState.selectionNotifier.addListener(_recount);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    widget.editorState.selectionNotifier.removeListener(_recount);
    super.dispose();
  }

  static int _countChars(Node node) {
    var count = node.delta?.toPlainText().runes.length ?? 0;
    for (final child in node.children) {
      count += _countChars(child);
    }
    return count;
  }

  void _recount() {
    final editorState = widget.editorState;
    final total = _countChars(editorState.document.root);
    var selected = 0;
    final selection = editorState.selection;
    if (selection != null && !selection.isCollapsed) {
      for (final line in editorState.getTextInSelection(selection)) {
        selected += line.replaceAll('\n', '').runes.length;
      }
    }
    if (total == _total && selected == _selected) return;
    if (!mounted) return;
    // 描画中の通知で呼ばれても安全なように、次のフレームで反映する。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted)
        setState(() {
          _total = total;
          _selected = selected;
        });
    });
  }

  static String _format(int n) => n.toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'),
    (m) => '${m[1]},',
  );

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontSize: 12, color: widget.color);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: widget.background.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_selected > 0) ...[
              Text(
                '${widget.selectedPrefix} ${_format(_selected)} ${widget.unit}',
                style: style,
              ),
              const SizedBox(width: 12),
            ],
            Text('${_format(_total)} ${widget.unit}', style: style),
          ],
        ),
      ),
    );
  }
}
