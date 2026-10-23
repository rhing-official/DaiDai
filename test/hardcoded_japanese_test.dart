import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// 表示言語の全画面対応（2026-10-13）の完了条件を機械的に守るテスト。画面に出す日本語の
// 文言は`lib/l10n/strings.dart`の`Strings`（日本語/English）へ置き、`lib/features/`
// （運営向け管理画面を除く）・`lib/widgets/`・`lib/utils/`のコードに日本語を直接書かない。
// コメント（`//`・`///`・`/* */`）は対象外。許可リストには「日本語のまま残す理由」を書く。

final _japanese = RegExp(r'[ぁ-んァ-ン一-龥]');

/// 行そのものを対象外にするパターン（ユーザーが通常目にしない文言）。
final _ignoredLine = RegExp(
  r'debugPrint\(|throw |UnimplementedError|StateError|^\s*_error = ',
);

/// 日本語のまま残す箇所（ファイル → 行に含まれる断片、理由付き）。
const _allowlist = <String, List<String>>{
  // 404ページの展示作品は日本語の作品名・解説が原文（英語は`titleEn`/`captionEn`で別に持つ）。
  'lib/features/not_found/not_found_screen.dart': ['title:', 'caption:'],
  // `Vocabulary`が無い場合の最終フォールバック（実際には常に`Vocabulary`が渡る）。
  'lib/features/chat/chat_screen.dart': ["?? 'ぺったん'"],
  // `debugPrint`の複数行引数の継続行（開発者向けログ）。
  'lib/features/calendar/calendar_sync_bootstrap.dart': ['CalendarSync:'],
  'lib/features/chat/talks_search.dart': ['メッセージ検索:'],
  // Androidの通知チャンネル名・説明（チャンネル作成時に固定され、バックグラウンドの
  // isolateでも作るためアプリの表示言語を引けない。システムの通知設定にだけ出る）。
  'lib/utils/android_notification_sound_sync.dart': [
    'メッセージ（カスタム音）',
    '新着メッセージの通知',
  ],
  // 曜日の略称は表示言語ごとの対訳表そのもの（英語は別の定数）。
  'lib/utils/message_time.dart': ['_weekdayAbbreviationsJa'],
  // 誕生日の表記は表示言語ごとの並び・単位の対訳表そのもの（英語・フランス語は別の
  // 月名の表）。見る人の言語で整形するため`Strings`の固定文言では表せない。
  'lib/utils/birthday_format.dart': [
    'AppLocale.japanese =>',
    '月\${birthday.day}日',
  ],
};

bool _isAllowed(String path, String line) {
  final fragments = _allowlist[path];
  return fragments != null && fragments.any(line.contains);
}

List<String> _scan(File file, String path) {
  final found = <String>[];
  var inBlock = false;
  var number = 0;
  for (final line in file.readAsLinesSync()) {
    number++;
    final trimmed = line.trim();
    if (inBlock) {
      if (trimmed.contains('*/')) inBlock = false;
      continue;
    }
    if (trimmed.startsWith('/*')) {
      if (!trimmed.contains('*/')) inBlock = true;
      continue;
    }
    if (trimmed.startsWith('//')) continue;
    // 行末の`//`コメントは、後ろに引用符が無い場合だけ落とす。
    var code = line;
    final comment = RegExp(r'(?<!:)//(?!/)').firstMatch(code);
    if (comment != null) {
      final after = code.substring(comment.end);
      if (!after.contains("'") && !after.contains('"')) {
        code = code.substring(0, comment.start);
      }
    }
    if (!_japanese.hasMatch(code)) continue;
    if (_ignoredLine.hasMatch(code)) continue;
    if (_isAllowed(path, code)) continue;
    found.add(
      '$path:$number: ${trimmed.length > 100 ? trimmed.substring(0, 100) : trimmed}',
    );
  }
  return found;
}

void main() {
  test('画面に出す日本語がコードに直書きされていない（許可リストを除く）', () {
    final roots = ['lib/features', 'lib/widgets', 'lib/utils'];
    final problems = <String>[];
    for (final root in roots) {
      for (final entity in Directory(root).listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final path = entity.path;
        if (path.startsWith('lib/features/admin/')) continue; // 運営専用（日本語固定）
        problems.addAll(_scan(entity, path));
      }
    }
    expect(
      problems,
      isEmpty,
      reason:
          '日本語の文言は`Strings`（lib/l10n/strings.dart）へ移すか、'
          '許可リストに理由付きで追加してください:\n${problems.join('\n')}',
    );
  });
}
