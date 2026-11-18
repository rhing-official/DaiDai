import 'package:daidai/l10n/app_locale.dart';
import 'package:daidai/features/chat/call_presence_mark.dart';
import 'package:daidai/providers/app_locale_provider.dart';
import 'package:daidai/providers/conversation_call_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('badgeは白い丸に黒いアイコン・人数で出る', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          initialAppLocaleProvider.overrideWithValue(AppLocale.japanese),
          conversationCallProvider('g1').overrideWith(
            (ref) => const ConversationCallPresence(
              users: [
                CallPresenceUser(userId: 'a', rhingSeed: 'a'),
                CallPresenceUser(userId: 'b', rhingSeed: 'b'),
              ],
              isVideo: false,
              isMine: false,
            ),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: CallPresenceMark(
              conversationId: 'g1',
              color: Colors.red,
              badge: true,
            ),
          ),
        ),
      ),
    );
    final icon = tester.widget<Icon>(find.byIcon(Icons.call));
    expect(icon.color, Colors.black);
    expect(find.text('2'), findsOneWidget);
    final decoration =
        tester.widget<DecoratedBox>(find.byType(DecoratedBox).first).decoration
            as ShapeDecoration;
    expect(decoration.color, Colors.white);
  });
}
