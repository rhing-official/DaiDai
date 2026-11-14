import 'package:daidai/models/group.dart';
import 'package:daidai/utils/group_permissions.dart';
import 'package:flutter_test/flutter_test.dart';

Group _group({bool countOnly = false}) => Group(
  groupId: 'g1',
  name: 'g',
  ownerId: 'u1',
  memberIds: const ['u1'],
  memberRoles: const {'u1': 'owner'},
  readReceiptsCountOnly: countOnly,
);

Room _room({bool custom = false, bool? override}) => Room(
  roomId: 'r1',
  groupId: 'g1',
  name: 'r',
  memberIds: const ['u1'],
  customSettingsEnabled: custom,
  readReceiptsCountOnlyOverride: override,
);

void main() {
  test('既定は誰が読んだかを出す（人数のみではない）', () {
    expect(effectiveReadReceiptsCountOnly(group: _group()), isFalse);
  });

  test('広場の設定が寄合に効く。寄合独自の設定がオンなら寄合の上書きが優先', () {
    final g = _group(countOnly: true);
    expect(effectiveReadReceiptsCountOnly(group: g, room: _room()), isTrue);
    // 独自の設定がオフなら、上書きがあっても広場の値。
    expect(
      effectiveReadReceiptsCountOnly(group: g, room: _room(override: false)),
      isTrue,
    );
    expect(
      effectiveReadReceiptsCountOnly(
        group: g,
        room: _room(custom: true, override: false),
      ),
      isFalse,
    );
    expect(
      effectiveReadReceiptsCountOnly(
        group: _group(),
        room: _room(custom: true, override: true),
      ),
      isTrue,
    );
  });

  test('JSONの往復。欠落していればfalse・null', () {
    final g = Group.fromJson('g1', {
      'name': 'g',
      'ownerId': 'u1',
      'memberIds': ['u1'],
      'memberRoles': {'u1': 'owner'},
    });
    expect(g.readReceiptsCountOnly, isFalse);
    expect(_group(countOnly: true).toJson()['readReceiptsCountOnly'], isTrue);
    expect(
      _room(override: true).toJson()['readReceiptsCountOnlyOverride'],
      isTrue,
    );
  });
}
