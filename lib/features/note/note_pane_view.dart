import 'dart:async';
import 'dart:io' show Platform;

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../l10n/strings.dart';
import '../../models/app_ui_style.dart';
import '../../models/app_user.dart';
import '../../models/note_op.dart';
import '../../providers/app_ui_style_provider.dart';
import '../../providers/repository_providers.dart';
import '../../theme/popup_surface_colors.dart';
import '../../utils/attachment_upload.dart';
import '../../utils/note_transaction_codec.dart';
import '../../widgets/glass/glass_app_bar.dart';
import '../../widgets/swipe_gestures.dart';

/// ダークテーマ（劇画は常時この扱い）でのノート本文の文字色（2026-09-07
/// 追加）。ライトモードはappflowy_editor既定の黒のまま変更しない
/// （ユーザー指示）。ベースの`text`を白にすれば`bold`/`italic`/
/// `underline`/`strikethrough`は色未指定のため自動的にこれを継承する
/// （`appflowy_rich_text.dart`が`textStyleConfiguration.text.copyWith(...)`
/// を土台にする実装のため）。`href`/`code`/`autoComplete`は既定で独自の
/// 色を持つため、明示的に上書きする。
const _kNoteDarkTextStyleConfiguration = TextStyleConfiguration(
  text: TextStyle(fontSize: 16, color: Colors.white),
  href: TextStyle(color: Colors.white, decoration: TextDecoration.underline),
  code: TextStyle(
    color: Colors.white,
    backgroundColor: Color.fromARGB(98, 0, 195, 255),
  ),
  autoComplete: TextStyle(color: Colors.white),
);

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

class _NotePaneViewState extends ConsumerState<NotePaneView> {
  EditorState? _editorState;
  EditorScrollController? _scrollController;
  final _titleController = TextEditingController();
  final _titleFocusNode = FocusNode();
  final _attachButtonKey = GlobalKey();
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

  bool get _isMobilePlatform =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  @override
  void initState() {
    super.initState();
    _load();
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
    final document = note != null && note.content.isNotEmpty
        ? Document.fromJson(note.content)
        : Document.blank(withInitialText: true);
    final editorState = EditorState(document: document);
    _transactionSub = editorState.transactionStream.listen(
      _handleLocalTransaction,
    );
    setState(() {
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
    if (_dirty && editorState != null) {
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
      SelectionMenuItem(
        getName: () => strings.noteMenuAttachment,
        icon: (editorState, isSelected, style) => SelectionMenuIconWidget(
          name: 'image',
          isSelected: isSelected,
          style: style,
        ),
        keywords: const ['attachment', 'file', 'image', 'video'],
        handler: (editorState, _, _) => _pickAndInsertAttachment(),
      ),
    ];
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

  /// 添付選択肢のポップアップを開く（2026-09-07、`showModalBottomSheet`から
  /// 変更）。AppBarの添付ボタン・本文中の「/」挿入メニューどちらから呼ばれた
  /// 場合も、見た目の一貫性のためAppBarの添付ボタンの位置を基準に開く
  /// （`chat_panes.dart`の`_NoteButtonState._openNotePopup`と同じ、
  /// ボタン直下にアンカーする`showMenu`+`RelativeRect`パターン）。
  Future<void> _pickAndInsertAttachment() async {
    final strings = ref.read(appStringsProvider);
    final buttonContext = _attachButtonKey.currentContext;
    if (buttonContext == null) return;
    final box = buttonContext.findRenderObject()! as RenderBox;
    final bottomLeft = box.localToGlobal(Offset(0, box.size.height));
    final bottomRight = box.localToGlobal(
      Offset(box.size.width, box.size.height),
    );
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(bottomLeft, bottomRight),
      Offset.zero & overlay.size,
    );
    final choice = await showMenu<String>(
      context: context,
      position: position,
      color: Colors.transparent,
      shadowColor: Colors.transparent,
      elevation: 0,
      items: [
        PopupMenuItem<String>(
          enabled: false,
          padding: EdgeInsets.zero,
          child: _AttachPopupContent(strings: strings),
        ),
      ],
    );
    if (choice == null || !mounted) return;
    switch (choice) {
      case 'image':
        final picked = await ImagePicker().pickImage(
          source: ImageSource.gallery,
        );
        if (picked == null) return;
        await _insertAttachment(
          bytes: await picked.readAsBytes(),
          fileName: picked.name,
          contentType: 'image',
        );
      case 'video':
        final picked = await ImagePicker().pickVideo(
          source: ImageSource.gallery,
        );
        if (picked == null) return;
        await _insertAttachment(
          bytes: await picked.readAsBytes(),
          fileName: picked.name,
          contentType: 'video',
        );
      case 'file':
        final file = await FilePicker.pickFile();
        if (file == null) return;
        await _insertAttachment(
          bytes: await file.readAsBytes(),
          fileName: file.name,
          contentType: 'file',
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final uiStyle = ref.watch(appUiStyleProvider);
    final isGlass = uiStyle == AppUiStyle.glass;

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
    final attachAction = IconButton(
      key: _attachButtonKey,
      icon: _uploading
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.attach_file),
      tooltip: '',
      onPressed: _uploading || _editorState == null
          ? null
          : _pickAndInsertAttachment,
    );

    // タイトル欄（appBar側の`titleField`）にフォーカスがある間にEscを押した
    // 場合も閉じられるよう、`Scaffold.body`だけでなく`appBar`も含めて
    // `Focus`で包む（appBarとbodyはフォーカスツリー上兄弟のため、body側だけ
    // 包んでもタイトル欄フォーカス中はこのハンドラの祖先チェーンに入らない、
    // 2026-09-07変更）。
    return Focus(
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
        appBar: isGlass
            ? GlassAppBar(
                leading: leadingButton,
                title: titleField,
                actions: [attachAction],
              )
            : AppBar(
                leading: leadingButton,
                title: titleField,
                actions: [attachAction],
              ),
        body: SwipeDownToDismiss(
          onDismiss: _close,
          child: _buildEditorBody(strings),
        ),
      ),
    );
  }

  Widget _buildEditorBody(Strings strings) {
    final editorState = _editorState;
    final scrollController = _scrollController;
    if (editorState == null || scrollController == null) {
      return const Center(child: CircularProgressIndicator());
    }
    // 「/」入力メニュー（note.comの「+」ボタンに相当）はappflowy_editorの
    // 仕様上デスクトップ/Web限定（`slash_command.dart`のPlatformExtension.
    // isMobileガード参照）。標準の`slashCommand`を、v1で対応する項目だけに
    // 絞った`customSlashCommand`に差し替える。
    final characterShortcutEvents = [
      customSlashCommand(_buildSelectionMenuItems(strings)),
      ...standardCharacterShortcutEvents.where((e) => e != slashCommand),
    ];
    // ライトモードはappflowy_editor既定の黒のまま（ユーザー指示）、
    // ダーク時（劇画は常時この扱い）のみ白へ統一する。
    final isGekiga = ref.watch(appUiStyleProvider) == AppUiStyle.gekiga;
    final isDark = isGekiga || Theme.of(context).brightness == Brightness.dark;
    final textStyleConfiguration = isDark
        ? _kNoteDarkTextStyleConfiguration
        : null;
    final editor = AppFlowyEditor(
      editorState: editorState,
      editorScrollController: scrollController,
      editorStyle: _isMobilePlatform
          ? EditorStyle.mobile(textStyleConfiguration: textStyleConfiguration)
          : EditorStyle.desktop(textStyleConfiguration: textStyleConfiguration),
      characterShortcutEvents: characterShortcutEvents,
      // 標準の`exitEditingCommand`（Escapeキー）は選択解除・ソフトキーボード
      // を閉じるだけで`KeyEventResult.handled`を返すため、エディタ本体に
      // フォーカスがある間はEscapeキーがここで消費されてしまい、外側の
      // `Focus.onKeyEvent`（`_close()`でノートを閉じる）まで伝播しなかった
      // （2026-09-07判明）。「/」入力メニューの`slashCommand`除外と同じ要領で
      // 除外し、Escapeを外側へ伝播させる。
      commandShortcutEvents: standardCommandShortcutEvents
          .where((e) => e != exitEditingCommand)
          .toList(),
      blockComponentBuilders: standardBlockComponentBuilderMap,
    );
    // フローティングツールバー・「/」メニューともにデスクトップ/Web限定の
    // ため、モバイルではMarkdownショートカット入力のみで見出し・リスト等を
    // 付けられる（2026-09-06時点の既知の制約）。
    if (_isMobilePlatform) return editor;
    return FloatingToolbar(
      items: _buildToolbarItems(),
      editorState: editorState,
      editorScrollController: scrollController,
      textDirection: TextDirection.ltr,
      child: editor,
    );
  }
}

/// 添付選択肢ポップアップの中身（2026-09-07追加）。`note_popup_content.dart`
/// の`_NotePopupContent`と同じ配色規約（`popup_surface_colors.dart`）に
/// 揃えた、画像/動画/ファイルの3択リスト。
class _AttachPopupContent extends ConsumerWidget {
  const _AttachPopupContent({required this.strings});

  final Strings strings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brightness = Theme.of(context).brightness;
    final uiStyle = ref.watch(appUiStyleProvider);
    final onInverse = popupCardForeground(brightness, uiStyle);

    Widget optionRow(IconData icon, String label, String value) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => Navigator.of(context).pop(value),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            child: Row(
              children: [
                Icon(icon, color: onInverse),
                const SizedBox(width: 12),
                Text(label, style: TextStyle(color: onInverse)),
              ],
            ),
          ),
        ),
      );
    }

    return SizedBox(
      width: 220,
      child: Container(
        decoration: BoxDecoration(
          color: popupCardBackground(brightness, uiStyle),
          border: Border.all(color: popupCardBorder(brightness, uiStyle)),
          borderRadius: BorderRadius.circular(16),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            optionRow(Icons.image_outlined, strings.chatAttachImage, 'image'),
            optionRow(
              Icons.videocam_outlined,
              strings.chatAttachVideo,
              'video',
            ),
            optionRow(Icons.attach_file, strings.chatAttachFile, 'file'),
          ],
        ),
      ),
    );
  }
}
