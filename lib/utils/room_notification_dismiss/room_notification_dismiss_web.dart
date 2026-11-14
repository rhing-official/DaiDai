import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Service Workerへ、その寄合の通知を閉じるよう依頼する。
void dismissWebRoomNotifications(String conversationId, String roomId) {
  try {
    final controller = web.window.navigator.serviceWorker.controller;
    if (controller == null) return;
    final message = <String, String>{
      'type': 'dismiss-room-notifications',
      'conversationId': conversationId,
      'roomId': roomId,
    }.jsify();
    controller.postMessage(message);
  } catch (_) {}
}
