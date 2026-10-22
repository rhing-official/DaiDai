import 'package:flutter_test/flutter_test.dart';

import 'package:daidai/models/group_invite_preview.dart';
import 'package:daidai/models/group_profile_card.dart';
import 'package:daidai/models/profile_card.dart';

void main() {
  group('GroupProfileCard の焦点', () {
    test('未設定ならキーを書かず、古いデータは焦点なしで読める', () {
      const card = GroupProfileCard(name: 'a');
      final json = card.toJson();
      expect(json.containsKey('iconFocal'), isFalse);
      expect(json.containsKey('backgroundFocal'), isFalse);
      final back = GroupProfileCard.fromJson(json);
      expect(back.iconFocal, isNull);
      expect(back.backgroundFocal, isNull);
    });

    test('焦点はJSONで往復し、clearで外せる', () {
      const focal = ImageFocal(dx: 0.5, dy: -0.25, scale: 2);
      final card = const GroupProfileCard(
        name: 'a',
      ).copyWith(iconFocal: focal, backgroundFocal: focal);
      final back = GroupProfileCard.fromJson(card.toJson());
      expect(back.iconFocal, focal);
      expect(back.backgroundFocal, focal);
      final cleared = back.copyWith(
        clearIconFocal: true,
        clearBackgroundFocal: true,
      );
      expect(cleared.iconFocal, isNull);
      expect(cleared.backgroundFocal, isNull);
    });
  });

  test('GroupInvitePreview も焦点を往復する', () {
    const focal = ImageFocal(dx: -1, scale: 1.5);
    const preview = GroupInvitePreview(name: 'a', iconFocal: focal);
    final back = GroupInvitePreview.fromJson(preview.toJson());
    expect(back.iconFocal, focal);
    expect(back.backgroundFocal, isNull);
  });
}
