import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daidai/models/link_preview.dart';
import 'package:daidai/providers/link_preview_provider.dart';
import 'package:daidai/widgets/link_preview_card.dart';

void main() {
  testWidgets('何も取れなかったURLもURLをタイトルにしたカードを出す', (tester) async {
    const url = 'https://www.pixiv.net/artworks/123';
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          linkPreviewProvider.overrideWith(
            (ref, u) async => LinkPreview(url: u),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: LinkPreviewCard(url: url, isGekiga: false, isMe: false),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('pixiv.net'), findsOneWidget);
    expect(find.text('www.pixiv.net/artworks/123'), findsOneWidget);
  });
}
