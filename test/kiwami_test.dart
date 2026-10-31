import 'package:daidai/l10n/app_locale.dart';
import 'package:daidai/models/app_user.dart';
import 'package:daidai/models/font_design.dart';
import 'package:daidai/models/kiwami_subscription_status.dart';
import 'package:daidai/models/subscription_plan.dart';
import 'package:daidai/providers/kiwami_providers.dart';
import 'package:daidai/providers/repository_providers.dart';
import 'package:daidai/repositories/user_repository.dart';
import 'package:daidai/utils/kiwami.dart';
import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// 極み（有料プラン）の登録（2026-10-17）: 契約状態・判定・極み限定フォント・
// 会話に極みの人がいるかの判定。

class _FakeUserRepository implements UserRepository {
  _FakeUserRepository(this.users);
  final Map<String, AppUser> users;

  @override
  Stream<AppUser?> watchUser(String userId) => Stream.value(users[userId]);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

AppUser _user(String id, {SubscriptionPlan plan = SubscriptionPlan.free}) =>
    AppUser(userId: id, rhingSeed: id, subscriptionPlan: plan);

Future<ProviderContainer> _container(Map<String, AppUser> users) async {
  final container = ProviderContainer(
    overrides: [
      userRepositoryProvider.overrideWithValue(_FakeUserRepository(users)),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  _channelTests();
  group('契約状態', () {
    test('名前から引け、不明・未設定は無料', () {
      expect(SubscriptionPlan.fromName('kiwami'), SubscriptionPlan.kiwami);
      expect(SubscriptionPlan.fromName('free'), SubscriptionPlan.free);
      expect(SubscriptionPlan.fromName(null), SubscriptionPlan.free);
      expect(SubscriptionPlan.fromName('???'), SubscriptionPlan.free);
    });

    test('住人データから読めるが、toJsonには含めない（全体上書きで消えない・書き戻さない）', () {
      final user = AppUser.fromJson(const {
        'userId': 'u1',
        'rhingSeed': 'a',
        'subscriptionPlan': 'kiwami',
      });
      expect(user.subscriptionPlan, SubscriptionPlan.kiwami);
      expect(user.toJson().containsKey('subscriptionPlan'), isFalse);
      expect(
        AppUser.fromJson(const {
          'userId': 'u2',
          'rhingSeed': 'b',
        }).subscriptionPlan,
        SubscriptionPlan.free,
      );
    });
  });

  group('極みの判定', () {
    test('課金が有効な間は、契約が極みの人だけが極み', () {
      expect(kKiwamiBillingEnabled, isTrue);
      expect(isKiwami(_user('a', plan: SubscriptionPlan.kiwami)), isTrue);
      expect(isKiwami(_user('b')), isFalse);
      expect(isKiwami(null), isFalse);
    });

    test('会話に1人でも極みがいれば、会話に極みがいる', () async {
      final container = await _container({
        'a': _user('a'),
        'b': _user('b', plan: SubscriptionPlan.kiwami),
      });
      // ストリームの最初の値を取り込む。
      container.listen(isKiwamiProvider('a'), (_, _) {});
      container.listen(isKiwamiProvider('b'), (_, _) {});
      await Future<void>.delayed(Duration.zero);
      expect(container.read(isKiwamiProvider('a')), isFalse);
      expect(container.read(isKiwamiProvider('b')), isTrue);
      container.listen(conversationHasKiwamiProvider('a,b'), (_, _) {});
      container.listen(conversationHasKiwamiProvider('a'), (_, _) {});
      await Future<void>.delayed(Duration.zero);
      expect(container.read(conversationHasKiwamiProvider('a,b')), isTrue);
      expect(container.read(conversationHasKiwamiProvider('a')), isFalse);
    });
  });

  group('極み限定フォント', () {
    test('極み限定は決めた10種で、標準のNoto Sans JPは無料', () {
      final exclusive = FontDesign.values
          .where((d) => d.isKiwamiExclusive)
          .toSet();
      expect(exclusive, {
        FontDesign.kiwiMaru,
        FontDesign.shipporiMincho,
        FontDesign.hannariMincho,
        FontDesign.zenOldMincho,
        FontDesign.kleeOne,
        FontDesign.yomogi,
        FontDesign.kaiseiDecol,
        FontDesign.kurobaraCinderella,
        FontDesign.pigmo01,
        FontDesign.popRumCute,
      });
      expect(FontDesign.notoSansJp.isKiwamiExclusive, isFalse);
      expect(FontDesign.fromName(null), FontDesign.zenMaruGothic);
    });

    test('極みでない人は、極み限定の選択でも表示は標準に戻る（保存値は変えない）', () {
      const exclusive = FontDesign.kiwiMaru;
      expect(
        exclusive.resolvedFor(AppLocale.japanese, kiwami: false),
        FontDesign.notoSansJp,
      );
      expect(
        exclusive.resolvedFor(AppLocale.japanese, kiwami: true),
        FontDesign.kiwiMaru,
      );
      // 無料のフォントは、極みでなくてもそのまま。
      expect(
        FontDesign.zenKakuGothicNew.resolvedFor(
          AppLocale.japanese,
          kiwami: false,
        ),
        FontDesign.zenKakuGothicNew,
      );
    });
  });
}

void _channelTests() {
  group('購入経路による金額の出し分け', () {
    test('ストア版のモバイルだけが専用の経路になり、他は標準', () {
      PurchaseChannel of(String d, TargetPlatform p, {bool web = false}) =>
          purchaseChannelFor(distribution: d, platform: p, isWeb: web);
      expect(of('', TargetPlatform.android), PurchaseChannel.standard);
      expect(of('app_store', TargetPlatform.iOS), PurchaseChannel.appStore);
      expect(
        of('google_play', TargetPlatform.android),
        PurchaseChannel.googlePlay,
      );
      // 定義とプラットフォームが合わない・Web・デスクトップは標準。
      expect(of('app_store', TargetPlatform.android), PurchaseChannel.standard);
      expect(of('google_play', TargetPlatform.iOS), PurchaseChannel.standard);
      expect(
        of('app_store', TargetPlatform.iOS, web: true),
        PurchaseChannel.standard,
      );
      expect(of('app_store', TargetPlatform.macOS), PurchaseChannel.standard);
      expect(
        of('google_play', TargetPlatform.windows),
        PurchaseChannel.standard,
      );
    });

    test('割増用のリンクが未設定の間は、全経路が標準のリンクを使う', () {
      final standard = kiwamiPaymentLinkFor(PurchaseChannel.standard);
      expect(kiwamiPaymentLinkFor(PurchaseChannel.appStore), standard);
      expect(kiwamiPaymentLinkFor(PurchaseChannel.googlePlay), standard);
    });

    test('購入ページのURLに、uidと経路が付く', () {
      final uri = kiwamiPurchaseUri(
        'abc123',
        channel: PurchaseChannel.appStore,
      );
      expect(uri.queryParameters['client_reference_id'], 'abc123__appStore');
      expect(
        kiwamiPurchaseUri(
          'abc123',
          channel: PurchaseChannel.standard,
        ).queryParameters['client_reference_id'],
        'abc123__standard',
      );
      // 既定（このテストの実行環境）は標準。
      expect(
        kiwamiPurchaseUri('abc123').queryParameters['client_reference_id'],
        'abc123__standard',
      );
    });

    test('割増後の金額は、手取りを保つ切り上げ（手数料15%で353円、10%で334円）', () {
      expect(surchargedPrice(kKiwamiBasePrice, 0.15), 353);
      expect(surchargedPrice(kKiwamiBasePrice, 0.10), 334);
      expect(surchargedPrice(kKiwamiBasePrice, 0), kKiwamiBasePrice);
    });

    test('契約状態に、購入経路と月額が載る（無ければnull）', () {
      final status = KiwamiSubscriptionStatus.fromJson({
        'state': 'active',
        'periodEnd': null,
        'channel': 'appStore',
        'monthlyAmount': 353,
      });
      expect(status.channel, 'appStore');
      expect(status.monthlyAmount, 353);
      final old = KiwamiSubscriptionStatus.fromJson({'state': 'none'});
      expect(old.channel, isNull);
      expect(old.monthlyAmount, isNull);
    });
  });
}
