import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

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

/// 購入経路（2026-10-20）。ストア版のモバイル（iOS App Store・Google Play）では、アプリ内の
/// リンクから決済するとストアの手数料がかかるため、その分を上乗せした金額の決済リンクを
/// 使う。Web・デスクトップ・APKの直接配布は手数料がかからず、元の金額（[standard]）。
enum PurchaseChannel { standard, appStore, googlePlay }

/// ビルド時に、ストア版だけが付ける定義（`--dart-define=DAIDAI_DISTRIBUTION=app_store`
/// または`google_play`）。付けなければ[PurchaseChannel.standard]。
const kDistribution = String.fromEnvironment('DAIDAI_DISTRIBUTION');

/// 購入経路を決める（判定だけの純粋な関数）。`app_store`はiOS、`google_play`はAndroidで
/// だけ有効。Web・それ以外は常に[PurchaseChannel.standard]。
PurchaseChannel purchaseChannelFor({
  required String distribution,
  required TargetPlatform platform,
  bool isWeb = false,
}) {
  if (isWeb) return PurchaseChannel.standard;
  if (distribution == 'app_store' && platform == TargetPlatform.iOS) {
    return PurchaseChannel.appStore;
  }
  if (distribution == 'google_play' && platform == TargetPlatform.android) {
    return PurchaseChannel.googlePlay;
  }
  return PurchaseChannel.standard;
}

/// 今動いているアプリの購入経路。
PurchaseChannel currentPurchaseChannel() => purchaseChannelFor(
  distribution: kDistribution,
  platform: defaultTargetPlatform,
  isWeb: kIsWeb,
);

/// 極み（月額300円）の元の金額（円）。
const kKiwamiBasePrice = 300;

/// 極みのStripe決済リンク（経路ごと）。`standard`は元の金額（2026-10-17）。ストア版用は、
/// Stripeに割増の商品・決済リンクを作ってからURLを入れる（空の間は`standard`のリンクを使う、
/// つまり割増は無効）。`client_reference_id`に購入者のuidと経路を付けて開くと、決済完了の
/// Webhook（`stripeWebhook`）がその住人へ付与する。
const kKiwamiPaymentLinks = <PurchaseChannel, String>{
  PurchaseChannel.standard: 'https://buy.stripe.com/9B6cN4dgh9s1e5A3nH1Jm00',
  // 例: 極み（アプリ経由・App Store）¥353/月（Apple手数料15%を上乗せ）。
  PurchaseChannel.appStore: '',
  // 例: 極み（アプリ経由・Google Play）¥334/月（Google手数料10%を上乗せ）。
  PurchaseChannel.googlePlay: '',
};

/// [channel]の決済リンク。未設定（空）なら`standard`のリンク。
String kiwamiPaymentLinkFor(PurchaseChannel channel) {
  final link = kKiwamiPaymentLinks[channel] ?? '';
  return link.isEmpty ? kKiwamiPaymentLinks[PurchaseChannel.standard]! : link;
}

/// 手数料率[feeRate]（0.15なら15%）を上乗せして、手取りを[base]円に保つ金額（円）。
/// `base ÷ (1 − 手数料率)`の切り上げ。Stripeに割増の価格を作る時の確認用
/// （300円・15%なら353円、10%なら334円）。
int surchargedPrice(int base, double feeRate) => (base / (1 - feeRate)).ceil();

/// 極みの購入ページのURL。購入者のuidと購入経路を`client_reference_id`に付ける。
Uri kiwamiPurchaseUri(String userId, {PurchaseChannel? channel}) {
  final resolved = channel ?? currentPurchaseChannel();
  return Uri.parse(kiwamiPaymentLinkFor(resolved)).replace(
    queryParameters: {'client_reference_id': '${userId}__${resolved.name}'},
  );
}
