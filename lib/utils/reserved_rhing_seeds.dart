/// 住人が取得できないRhing Seed（運営・システムを連想させる名前のなりすまし
/// 防止、2026-10-10追加）。お便り（運営の発信元）を住人ではなく
/// `announcements`・`system/official`へ移したことで、旧`@tayori`を住人が
/// 取れるようになるのを防ぐ。`firestore.rules`の`users`作成ルールの一覧と
/// 同じにすること。
const kReservedRhingSeeds = {'tayori', 'official', 'daidai', 'admin'};

/// [rhingSeed]（大文字小文字は無視）が予約済みで取得できないか。
bool isReservedRhingSeed(String rhingSeed) {
  return kReservedRhingSeeds.contains(rhingSeed.trim().toLowerCase());
}
