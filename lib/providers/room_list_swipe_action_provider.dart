import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/room_list_swipe_action.dart';

const _prefsKey = 'roomListSwipeAction';

/// 端末に保存されている初期値。`main()`で起動前に読み込んで渡す（未指定のテストでは
/// 既定の[RoomListSwipeAction.openRoom]）。
final initialRoomListSwipeActionProvider = Provider<RoomListSwipeAction>(
  (ref) => RoomListSwipeAction.openRoom,
);

Future<RoomListSwipeAction> loadInitialRoomListSwipeAction() async {
  final prefs = await SharedPreferences.getInstance();
  return RoomListSwipeAction.fromName(prefs.getString(_prefsKey));
}

/// 縦表示の寄合一覧の横スワイプの割り当て（2026-11-08）。操作の好みなので、
/// 端末ごとに保存し、アカウントには同期しない（`categoryListVerticalProvider`と同じ）。
class RoomListSwipeActionNotifier extends Notifier<RoomListSwipeAction> {
  @override
  RoomListSwipeAction build() => ref.watch(initialRoomListSwipeActionProvider);

  Future<void> setAction(RoomListSwipeAction action) async {
    state = action;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, action.name);
  }
}

final roomListSwipeActionProvider =
    NotifierProvider<RoomListSwipeActionNotifier, RoomListSwipeAction>(
      RoomListSwipeActionNotifier.new,
    );
