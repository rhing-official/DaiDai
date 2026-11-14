import 'package:daidai/models/room_list_swipe_action.dart';
import 'package:daidai/providers/room_list_swipe_action_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('保存値が無い・不明な時は、標準の「メニューのタブを切り替える」（2026-11-15）', () async {
    expect(RoomListSwipeAction.fromName(null), RoomListSwipeAction.switchTab);
    expect(RoomListSwipeAction.fromName('zzz'), RoomListSwipeAction.switchTab);
    expect(
      await loadInitialRoomListSwipeAction(),
      RoomListSwipeAction.switchTab,
    );
    expect(
      RoomListSwipeAction.fromName('openRoom'),
      RoomListSwipeAction.openRoom,
    );
  });

  test('切り替えた値は端末に保存され、次の起動で読み込める', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(
      container.read(roomListSwipeActionProvider),
      RoomListSwipeAction.switchTab,
    );
    await container
        .read(roomListSwipeActionProvider.notifier)
        .setAction(RoomListSwipeAction.openRoom);
    expect(
      container.read(roomListSwipeActionProvider),
      RoomListSwipeAction.openRoom,
    );
    expect(
      await loadInitialRoomListSwipeAction(),
      RoomListSwipeAction.openRoom,
    );
  });
}
