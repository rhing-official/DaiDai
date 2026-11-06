/// 相手の呼び名を決める（2026-11-06）。優先順位は、自分が指定した呼び名 >
/// 相手の呼び名 > `@Rhing Seed`。空白だけの値は無いものとして扱う。
/// 他の人にも見える場所（メンションの本文・招待リンク・運営画面）では使わない。
String resolveDisplayName({
  required String? alias,
  required String? nickname,
  required String rhingSeed,
}) {
  final a = alias?.trim();
  if (a != null && a.isNotEmpty) return a;
  final n = nickname?.trim();
  if (n != null && n.isNotEmpty) return n;
  return '@$rhingSeed';
}

/// [aliases]（相手のuserId→呼び名）から[userId]への指定を取り出す。無ければnull。
String? aliasOf(Map<String, String>? aliases, String userId) {
  final value = aliases?[userId]?.trim();
  return (value == null || value.isEmpty) ? null : value;
}
