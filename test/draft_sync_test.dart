import 'dart:async';
import 'dart:typed_data';

import 'package:daidai/features/chat/chat_screen.dart';
import 'package:daidai/features/chat/pending_attachment_tray.dart';
import 'package:daidai/l10n/app_locale.dart';
import 'package:daidai/models/app_ui_style.dart';
import 'package:daidai/models/chat_layout_style.dart';
import 'package:daidai/models/conversation_prefs.dart';
import 'package:daidai/models/draft_file.dart';
import 'package:daidai/models/message.dart';
import 'package:daidai/models/message_time_format.dart';
import 'package:daidai/models/send_key_mode.dart';
import 'package:daidai/providers/app_locale_provider.dart';
import 'package:daidai/providers/app_ui_style_provider.dart';
import 'package:daidai/providers/chat_layout_style_provider.dart';
import 'package:daidai/providers/draft_sync_enabled_provider.dart';
import 'package:daidai/providers/message_time_format_provider.dart';
import 'package:daidai/providers/repository_providers.dart';
import 'package:daidai/providers/send_key_mode_provider.dart';
import 'package:daidai/repositories/conversation_prefs_repository.dart';
import 'package:daidai/repositories/draft_file_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 再発防止（2026-11-27）。入力欄の下書き同期。コンピューターは語らいを開くと入力欄へ自動で
/// カーソルが合うので、フォーカスが有っても、他の端末の下書きが反映される。ファイルも反映される。
class _FakePrefs implements ConversationPrefsRepository {
  final controller =
      StreamController<Map<String, ConversationPrefs>>.broadcast();
  final writtenDrafts = <String>[];

  @override
  Stream<Map<String, ConversationPrefs>> watchAll(String userId) =>
      controller.stream;

  @override
  Future<void> setDraft({
    required String userId,
    required String conversationId,
    required String roomId,
    required String draft,
  }) async => writtenDrafts.add(draft);

  @override
  Future<void> setDraftFiles({
    required String userId,
    required String conversationId,
    required String roomId,
    required List<DraftFile> files,
  }) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

class _FakeFiles implements DraftFileRepository {
  @override
  Future<Uint8List?> download(String path, int maxBytes) async =>
      Uint8List.fromList([1, 2, 3]);

  @override
  Future<void> delete(String path) async {}

  @override
  Future<String> upload({
    required String userId,
    required String conversationId,
    required String roomId,
    required String fileId,
    required Uint8List bytes,
    required String contentType,
  }) async => 'draftFiles/$fileId';
}

Map<String, ConversationPrefs> _prefs({
  String? draft,
  List<DraftFile> files = const [],
}) => {
  'c1': ConversationPrefs(
    draftByRoom: {if (draft != null) 'r1': draft},
    draftFilesByRoom: {if (files.isNotEmpty) 'r1': files},
  ),
};

Future<_FakePrefs> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(600, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final prefs = _FakePrefs();
  addTearDown(prefs.controller.close);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        initialSendKeyModeProvider.overrideWithValue(SendKeyMode.enterToSend),
        initialMessageTimeFormatProvider.overrideWithValue(
          MessageTimeFormat.h24,
        ),
        initialAppLocaleProvider.overrideWithValue(AppLocale.japanese),
        initialChatLayoutStyleProvider.overrideWithValue(
          ChatLayoutStyle.sideBySide,
        ),
        initialAppUiStyleProvider.overrideWithValue(AppUiStyle.flat),
        initialDraftSyncEnabledProvider.overrideWithValue(true),
        conversationPrefsRepositoryProvider.overrideWithValue(prefs),
        draftFileRepositoryProvider.overrideWithValue(_FakeFiles()),
      ],
      child: MaterialApp(
        home: ChatScreen(
          title: 't',
          currentUserId: 'u1',
          conversationId: 'c1',
          roomId: 'r1',
          isDm: true,
          messagesStream: Stream.value(<Message>[]),
          onSend:
              (
                content, {
                silent = false,
                replyTo,
                mentions = MessageMentions.none,
                sendAt,
              }) async {},
          onSendAttachment:
              (attachment, {onProgress, caption, replyTo, sendAt}) async {},
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  return prefs;
}

void main() {
  testWidgets('入力欄にフォーカスが有っても、他の端末の下書きが反映される', (tester) async {
    final prefs = await _pump(tester);
    await tester.tap(find.byType(TextField));
    await tester.pump();
    prefs.controller.add(_prefs(draft: 'こんにちは'));
    await tester.pump();
    await tester.pump();
    expect(find.text('こんにちは'), findsOneWidget);
    // 他の端末で消された（送った）下書きも、反映される。
    prefs.controller.add(_prefs());
    await tester.pump();
    await tester.pump();
    expect(find.text('こんにちは'), findsNothing);
  });

  testWidgets('自分が入力している間（保存待ち）は、他の端末の下書きで上書きしない', (tester) async {
    final prefs = await _pump(tester);
    await tester.enterText(find.byType(TextField), '入力中');
    await tester.pump();
    prefs.controller.add(_prefs(draft: '他の端末'));
    await tester.pump();
    expect(find.text('入力中'), findsOneWidget);
    expect(find.text('他の端末'), findsNothing);
    // 保存が済めば（600ms後）、その後に届いたものは反映される。
    await tester.pump(const Duration(seconds: 1));
    expect(prefs.writtenDrafts, ['入力中']);
    prefs.controller.add(_prefs(draft: '他の端末'));
    await tester.pump();
    await tester.pump();
    expect(find.text('他の端末'), findsOneWidget);
  });

  testWidgets('自分の書き込みの反響は、入力欄を書き換えない', (tester) async {
    final prefs = await _pump(tester);
    await tester.enterText(find.byType(TextField), 'abc');
    await tester.pump(const Duration(seconds: 1));
    // 続けて入力した後に、先の書き込みの反響が届いても、戻らない。
    await tester.enterText(find.byType(TextField), 'abcd');
    await tester.pump(const Duration(seconds: 1));
    prefs.controller.add(_prefs(draft: 'abcd'));
    await tester.pump();
    expect(find.text('abcd'), findsOneWidget);
  });

  testWidgets('他の端末の下書きのファイルが、トレイへ入り、外れると消える', (tester) async {
    final prefs = await _pump(tester);
    expect(find.byType(PendingAttachmentTray), findsNothing);
    prefs.controller.add(
      _prefs(
        files: const [
          DraftFile(
            id: 'f1',
            name: 'memo.txt',
            contentType: 'file',
            path: 'draftFiles/u1/c1/r1/f1',
            size: 3,
          ),
        ],
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(find.byType(PendingAttachmentTray), findsOneWidget);
    prefs.controller.add(_prefs());
    await tester.pump();
    await tester.pump();
    expect(find.byType(PendingAttachmentTray), findsNothing);
  });
}
