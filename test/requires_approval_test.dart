import 'package:daidai/models/group.dart';
import 'package:daidai/models/group_invite_preview.dart';
import 'package:flutter_test/flutter_test.dart';

// 参加に承認が必要か（2026-10-11）。欠落した既存文書は承認必須のまま読む。
void main() {
  Map<String, dynamic> groupJson() => {
    'name': 'g',
    'ownerId': 'o',
    'memberIds': ['o'],
    'memberRoles': {'o': 'owner'},
  };

  test('Group: 既存文書（フィールド欠落）は承認必須', () {
    expect(Group.fromJson('g1', groupJson()).requiresApproval, isTrue);
  });

  test('Group: falseは承認不要として読み、書き戻せる', () {
    final group = Group.fromJson('g1', {
      ...groupJson(),
      'requiresApproval': false,
    });
    expect(group.requiresApproval, isFalse);
    expect(group.toJson()['requiresApproval'], false);
  });

  test('招待プレビュー: 欠落は承認必須、falseは承認不要', () {
    expect(GroupInvitePreview.fromJson({'name': 'g'}).requiresApproval, isTrue);
    expect(
      GroupInvitePreview.fromJson({
        'name': 'g',
        'requiresApproval': false,
      }).requiresApproval,
      isFalse,
    );
  });
}
