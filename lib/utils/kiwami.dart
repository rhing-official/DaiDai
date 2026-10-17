import '../models/app_user.dart';
import '../models/subscription_plan.dart';

/// 極みの課金スイッチ（2026-10-17、有料化のため`true`）。`true`の間は
/// [SubscriptionPlan.kiwami]の人だけが極み。`false`にすると、契約状態に関わらず
/// 全員が極み扱い（2026-09-14の「全員に無料開放」へ戻せる）。
const kKiwamiBillingEnabled = true;

/// [user]が極みを使えるか。ユーザー情報が未取得（`null`）の間は、課金が有効なら
/// 極みでないものとして扱う。
bool isKiwami(AppUser? user) =>
    !kKiwamiBillingEnabled || user?.subscriptionPlan == SubscriptionPlan.kiwami;

/// 極み（月額300円）のStripe決済リンク（2026-10-17）。`client_reference_id`に購入者の
/// uidを付けて開くと、決済完了のWebhook（`stripeWebhook`）がその住人へ付与する。
const kKiwamiPaymentLink = 'https://buy.stripe.com/9B6cN4dgh9s1e5A3nH1Jm00';

Uri kiwamiPurchaseUri(String userId) => Uri.parse(
  kKiwamiPaymentLink,
).replace(queryParameters: {'client_reference_id': userId});
