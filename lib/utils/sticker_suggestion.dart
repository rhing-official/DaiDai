import '../models/sticker.dart';
import '../models/sticker_role.dart';
import 'text_normalize.dart';

/// 略語・打ちかけでも候補に出すため、3文字以上のキーワードは、先頭2文字が
/// 本文に含まれ、**その後ろも、キーワードと食い違うまで合っている**ときに一致とする
/// （例: 「おめ」「おめー」「おめでと」で「おめでとう」。2026-10-29追加）。
/// 食い違った文字が、ひらがな・カタカナ・漢字・英数字なら、別の言葉とみなして
/// 不一致（「おめん」「おめでたい」では出さない）。伸ばし棒・句読点・記号・空白、
/// または本文の終わりなら一致。先頭の文字だけを見るのは、どの部分でもよいとすると、
/// 「ありがとう」の「とう」が「おめでとう」に一致するような誤りが増えるため。
/// 1〜2文字のキーワード（「祝」「りょ」等）は、まるごと一致のみ。
const int _abbreviationPrefixLength = 2;

/// 言葉の一部になる文字か（ひらがな・漢字・英数字）。カタカナは
/// [normalizeForMatch]でひらがなになっている前提。伸ばし棒（ー）や記号・空白は含まない。
bool _isWordRune(int rune) {
  return (rune >= 0x3041 && rune <= 0x3096) || // ひらがな
      (rune >= 0x4E00 && rune <= 0x9FFF) || // 漢字
      rune == 0x3005 || // 々
      (rune >= 0x30 && rune <= 0x39) || // 0-9
      (rune >= 0x61 && rune <= 0x7A) || // a-z（小文字化済み）
      (rune >= 0xFF10 && rune <= 0xFF19) || // 全角数字
      (rune >= 0xFF41 && rune <= 0xFF5A); // 全角英小文字
}

/// [normalizedText]（[normalizeForMatch]済み）が、[keyword]に一致するか。
bool keywordMatches(String normalizedText, String keyword) {
  final normalizedKeyword = normalizeForMatch(keyword);
  if (normalizedKeyword.isEmpty) return false;
  if (normalizedText.contains(normalizedKeyword)) return true;

  final keywordRunes = normalizedKeyword.runes.toList();
  if (keywordRunes.length <= _abbreviationPrefixLength) return false;
  final textRunes = normalizedText.runes.toList();

  for (var i = 0; i + _abbreviationPrefixLength <= textRunes.length; i++) {
    // キーワードの先頭2文字が、ここから始まっているか
    var k = 0;
    while (k < _abbreviationPrefixLength &&
        textRunes[i + k] == keywordRunes[k]) {
      k++;
    }
    if (k < _abbreviationPrefixLength) continue;
    // 3文字目以降も、食い違うまで進める
    while (k < keywordRunes.length &&
        i + k < textRunes.length &&
        textRunes[i + k] == keywordRunes[k]) {
      k++;
    }
    // 本文の終わりまで合っていた（打ちかけ）
    if (i + k >= textRunes.length) return true;
    // 食い違った文字が、言葉の一部でなければ（伸ばし棒・記号・空白）、略語として一致
    if (!_isWordRune(textRunes[i + k])) return true;
  }
  return false;
}

/// メッセージ本文の内容に応じたぺったん提案（2026-09-05追加、
/// `lib/features/chat/chat_screen.dart`の`_onComposerTextChanged`から
/// 呼ばれる想定）。[roles]の中から`keywords`のいずれかが[messageText]に
/// 部分一致する役割idを集め、[candidates]の中でその役割idを1つ以上
/// `Sticker.roles`に持つスタンプを、一致した役割数が多い順に返す
/// （同数のものは`candidates`内の順序を維持する。Dartの`List.sort`は
/// 安定ソートではないため`mergeSort`相当の安定性は保証しない点に注意）。
///
/// 形態素解析・類義語辞書等は導入せず、ひらがな/カタカナ正規化＋大文字
/// 小文字統一をした上での単純な部分一致に留める（LINEの「おすすめ
/// スタンプ」機能等の競合調査、競合調査.md 2026-09-05付エントリ参照。
/// 表記ゆれ対応の精度をLINE並みに最初から作り込むのはコスト高なため、
/// まず簡易な一致から始める方針）。
List<Sticker> suggestStickers({
  required String messageText,
  required List<StickerRole> roles,
  required List<Sticker> candidates,
}) {
  final normalizedText = normalizeForMatch(messageText);
  if (normalizedText.isEmpty) return const [];

  final matchedRoleIds = <String>{};
  for (final role in roles) {
    final hasMatch = role.keywords.any(
      (keyword) => keywordMatches(normalizedText, keyword),
    );
    if (hasMatch) matchedRoleIds.add(role.roleId);
  }
  if (matchedRoleIds.isEmpty) return const [];

  final scored = <MapEntry<Sticker, int>>[];
  for (final sticker in candidates) {
    final matchCount = sticker.roles.where(matchedRoleIds.contains).length;
    if (matchCount > 0) scored.add(MapEntry(sticker, matchCount));
  }
  scored.sort((a, b) => b.value.compareTo(a.value));
  return scored.map((e) => e.key).toList();
}
