import 'package:daidai/l10n/app_locale.dart';
import 'package:daidai/models/app_user.dart';
import 'package:daidai/models/font_design.dart';
import 'package:daidai/models/subscription_plan.dart';
import 'package:daidai/providers/kiwami_providers.dart';
import 'package:daidai/providers/repository_providers.dart';
import 'package:daidai/repositories/user_repository.dart';
import 'package:daidai/utils/kiwami.dart';
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
      expect(FontDesign.fromName(null), FontDesign.notoSansJp);
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
