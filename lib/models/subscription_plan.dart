/// 契約プラン（2026-10-17追加）。`free`（無料）と`kiwami`（有料プラン「極み」）。
/// 付与・解除はサーバー（Cloud Functions `setKiwamiPlan`、管理者のみ）だけが行い、
/// クライアントからは書けない（`firestore.rules`の`users`で強制）。
enum SubscriptionPlan {
  free,
  kiwami;

  static SubscriptionPlan fromName(String? name) => SubscriptionPlan.values
      .firstWhere((p) => p.name == name, orElse: () => SubscriptionPlan.free);
}
