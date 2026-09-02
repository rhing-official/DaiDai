/// 語らい一覧（一対・広場）の並べ替え順。端末ごとの個人設定
/// （2026-09-02追加）。どのモードでもピン留めした語らいは常に最優先で
/// 表示され、この設定はピン留め内・ピン留め外それぞれの並び順を決める。
enum ConversationSortOrder {
  /// 最近会話した順（既定）。`lastMessageAt`降順。
  recent,

  /// 五十音順。読み仮名データを持たないため、相手の呼び名/広場名の先頭文字が
  /// 属する文字種（ひらがな→カタカナ→漢字→それ以外）で大まかに分類し、
  /// 同じ文字種内はコードポイント順で近似する（`lib/utils/kana_sort.dart`）。
  kana,

  /// 未読メッセージがある語らいを優先的に上位に出した上で、その中・その外
  /// それぞれを最近会話した順にする。
  unreadFirst;

  static ConversationSortOrder fromName(String? name) {
    return ConversationSortOrder.values.firstWhere(
      (order) => order.name == name,
      orElse: () => ConversationSortOrder.recent,
    );
  }
}
