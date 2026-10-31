import 'package:daidai/features/chat/user_profile_card_dialog.dart';
import 'package:daidai/models/app_user.dart';
import 'package:daidai/models/friend_request.dart';
import 'package:daidai/l10n/app_locale.dart';
import 'package:daidai/providers/app_locale_provider.dart';
import 'package:daidai/providers/repository_providers.dart';
import 'package:daidai/repositories/friend_repository.dart';
import 'package:daidai/widgets/profile_card_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FriendRepo implements FriendRepository {
  @override
  Future<bool> isFriend({
    required String userId,
    required String otherUserId,
  }) async => true;

  @override
  Future<FriendRequest?> getRequest(String a, String b) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// 相手のプロフィールカードのダイアログ（2026-10-31）。カードの領域が常に4:5で、
// 四隅が角丸の`ClipRRect`で切られ、送信ボタンがカードの内側に収まること。
void main() {
  for (final size in [const Size(436, 838), const Size(1200, 900)]) {
    testWidgets('カードは4:5・角丸・送信ボタンはカード内 $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      const me = AppUser(userId: 'me', rhingSeed: 'me');
      const other = AppUser(userId: 'other', rhingSeed: 'other');
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            initialAppLocaleProvider.overrideWithValue(AppLocale.japanese),
            friendRepositoryProvider.overrideWithValue(_FriendRepo()),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () => UserProfileCardDialog.show(
                  context,
                  currentUser: me,
                  user: other,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final card = tester.getRect(find.byType(ProfileCardView));
      expect(card.width / card.height, closeTo(0.8, 0.001));
      final clip = find.ancestor(
        of: find.byType(ProfileCardView),
        matching: find.byWidgetPredicate(
          (w) => w is ClipRRect && w.borderRadius == BorderRadius.circular(16),
        ),
      );
      expect(clip, findsWidgets);
      final send = tester.getRect(find.byIcon(Icons.send_outlined));
      expect(card.contains(send.topLeft), isTrue);
      expect(card.contains(send.bottomRight), isTrue);
    });
  }
}
