// DO NOT EDIT. This is code generated via package:intl/generate_localized.dart
// This is a library that provides messages for a ja_JP locale. All the
// messages from the main program should be duplicated here with the same
// function name.

// Ignore issues from commonly used lints in this file.
// ignore_for_file:unnecessary_brace_in_string_interps, unnecessary_new
// ignore_for_file:prefer_single_quotes,comment_references, directives_ordering
// ignore_for_file:annotate_overrides,prefer_generic_function_type_aliases
// ignore_for_file:unused_import, file_names, avoid_escaping_inner_quotes
// ignore_for_file:unnecessary_string_interpolations, unnecessary_string_escapes

import 'package:intl/intl.dart';
import 'package:intl/message_lookup_by_library.dart';

final messages = new MessageLookup();

typedef String MessageIfAbsent(String messageStr, List<dynamic> args);

class MessageLookup extends MessageLookupByLibrary {
  String get localeName => 'ja';

  final messages = _notInlinedMessages(_notInlinedMessages);
  static Map<String, Function> _notInlinedMessages(_) => <String, Function>{
        // DaiDai patch（2026-10-04）: 表の行/列メニューが英語のままだったため追加。
        "clearHighlightColor": MessageLookupByLibrary.simpleMessage("背景色を解除"),
        "highlightColor": MessageLookupByLibrary.simpleMessage("背景色"),
        "backgroundColor": MessageLookupByLibrary.simpleMessage("背景色"),
        "colAddAfter": MessageLookupByLibrary.simpleMessage("右に追加"),
        "colAddBefore": MessageLookupByLibrary.simpleMessage("左に追加"),
        "colClear": MessageLookupByLibrary.simpleMessage("内容を消去"),
        "colDuplicate": MessageLookupByLibrary.simpleMessage("複製"),
        "colRemove": MessageLookupByLibrary.simpleMessage("削除"),
        "rowAddAfter": MessageLookupByLibrary.simpleMessage("下に追加"),
        "rowAddBefore": MessageLookupByLibrary.simpleMessage("上に追加"),
        "rowClear": MessageLookupByLibrary.simpleMessage("内容を消去"),
        "rowDuplicate": MessageLookupByLibrary.simpleMessage("複製"),
        "rowRemove": MessageLookupByLibrary.simpleMessage("削除"),
      };
}
