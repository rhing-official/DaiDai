import 'package:daidai/widgets/always_animated_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('端末がアニメーションをオフにしていても、子孫では常にオン', (tester) async {
    bool? seen;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: AlwaysAnimations(
          child: Builder(
            builder: (context) {
              seen = MediaQuery.disableAnimationsOf(context);
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    expect(seen, isFalse);
  });
}
