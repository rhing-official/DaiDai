import 'text_normalize.dart';

/// `@`メンションの候補の種類（2026-10-11追加）。
enum MentionKind { user, role, everyone }

/// 入力欄の`@`サジェストに出す候補1件。[label]は`@`を除いた表示名で、本文には
/// `@$label`の形で挿入される。
class MentionCandidate {
  const MentionCandidate({
    required this.kind,
    required this.id,
    required this.label,
    this.subtitle,
    this.color,
  });

  final MentionKind kind;

  /// ユーザーならuserId、ロールならroleId、everyoneなら空文字。
  final String id;
  final String label;

  /// メンバーならrhingSeed、その他・ロールなら説明文。
  final String? subtitle;

  /// ロールの色（0xRRGGBB、nullなら既定の文字色）。
  final int? color;

  /// 本文に挿入される文字列（`@`込み）。
  String get insertText => '@$label';
}

/// カーソル直前の`@クエリ`。[start]は`@`の位置、[query]は`@`以降の文字列。
class MentionQuery {
  const MentionQuery({required this.start, required this.query});

  final int start;
  final String query;
}

/// [text]の[cursor]直前にメンション入力中の`@クエリ`があればそれを返す。
/// メンションに使えるのは半角の`@`のみ（全角`＠`は対象外）。`@`は行頭か空白の
/// 直後でなければならない（メールアドレスのような`a@b`を誤検出しないため）。
/// クエリに空白は含められない（空白を打った時点でメンション入力は終わり）。
MentionQuery? detectMentionQuery(String text, int cursor) {
  if (cursor < 0 || cursor > text.length) return null;
  final head = text.substring(0, cursor);
  final match = RegExp(r'(^|\s)@([^\s@]*)$').firstMatch(head);
  if (match == null) return null;
  final query = match.group(2)!;
  return MentionQuery(start: cursor - query.length - 1, query: query);
}

/// [query]で[candidates]を絞り込む（ひらがな/カタカナ・大小文字の表記ゆれを
/// 吸収した部分一致、前方一致を先に並べる）。表示名・補足（rhingSeed）の
/// どちらに一致してもよい。空クエリなら全件を返す。
List<MentionCandidate> filterMentionCandidates(
  List<MentionCandidate> candidates,
  String query,
) {
  final q = normalizeForMatch(query);
  if (q.isEmpty) return candidates;
  final prefix = <MentionCandidate>[];
  final partial = <MentionCandidate>[];
  for (final c in candidates) {
    final label = normalizeForMatch(c.label);
    final sub = normalizeForMatch(c.subtitle ?? '');
    final seed = c.kind == MentionKind.user ? sub : '';
    if (label.startsWith(q) || seed.startsWith(q)) {
      prefix.add(c);
    } else if (label.contains(q) || seed.contains(q)) {
      partial.add(c);
    }
  }
  return [...prefix, ...partial];
}

/// 送信時に、本文中に残っているメンションだけを拾う。ユーザーが挿入後に
/// `@名前`を消した場合は宛先から外す（本文と宛先を食い違わせない）。
/// [selected]は挿入済みの候補、[text]は送信する本文。
List<MentionCandidate> mentionsStillInText(
  String text,
  Iterable<MentionCandidate> selected,
) {
  final seen = <String>{};
  final result = <MentionCandidate>[];
  for (final c in selected) {
    if (!text.contains(c.insertText)) continue;
    if (seen.add('${c.kind.name}:${c.id}')) result.add(c);
  }
  return result;
}
