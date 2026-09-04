import '../models/sticker.dart';
import '../models/sticker_role.dart';

/// メッセージ本文の内容に応じたペタピタ提案（2026-09-05追加、
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
  final normalizedText = _normalize(messageText);
  if (normalizedText.isEmpty) return const [];

  final matchedRoleIds = <String>{};
  for (final role in roles) {
    final hasMatch = role.keywords.any(
      (keyword) => normalizedText.contains(_normalize(keyword)),
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

/// カタカナ→ひらがな変換＋大文字小文字統一（2026-09-05追加）。
/// 「ありがとう」と「アリガトウ」、"OK"と"ok"のような表記ゆれを
/// 部分一致の対象として吸収するための簡易正規化。
String _normalize(String input) {
  final buffer = StringBuffer();
  for (final rune in input.toLowerCase().runes) {
    // カタカナ（ァ-ヶ、0x30A1-0x30F6）は+0x60した位置に対応するひらがな
    // （ぁ-ゖ、0x3041-0x3096）があるため、そのまま引き算で変換できる。
    if (rune >= 0x30A1 && rune <= 0x30F6) {
      buffer.writeCharCode(rune - 0x60);
    } else {
      buffer.writeCharCode(rune);
    }
  }
  return buffer.toString();
}
