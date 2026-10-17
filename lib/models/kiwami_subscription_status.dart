/// 極みの契約状態（運営向け、2026-10-18追加）。Stripeから取得した値で、
/// 住人データの`subscriptionPlan`（クライアントが読む判定用）とは別。
enum KiwamiSubscriptionState {
  /// Stripeの契約なし（手動付与・無料）。
  none,

  /// 継続中。
  active,

  /// 解約済みで、期間満了まで極みが使える。
  cancelScheduled,

  /// 支払い遅延。
  pastDue,

  /// 終了済み。
  ended;

  static KiwamiSubscriptionState fromName(String? name) =>
      values.firstWhere((s) => s.name == name, orElse: () => none);
}

class KiwamiSubscriptionStatus {
  const KiwamiSubscriptionStatus(this.state, {this.periodEnd});

  factory KiwamiSubscriptionStatus.fromJson(Map<String, dynamic> json) {
    final end = json['periodEnd'];
    return KiwamiSubscriptionStatus(
      KiwamiSubscriptionState.fromName(json['state'] as String?),
      periodEnd: end is String ? DateTime.tryParse(end)?.toLocal() : null,
    );
  }

  final KiwamiSubscriptionState state;

  /// 継続中は次回の更新日、解約予定は終了日。
  final DateTime? periodEnd;
}
