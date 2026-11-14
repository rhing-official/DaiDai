/// 寄合を開いた時に、Webで出ている通知を閉じる（2026-11-14）。Service Workerへ依頼する
/// （`web/firebase-messaging-sw.js`の`message`リスナー）。Web以外は何もしない。
library;

export 'room_notification_dismiss_stub.dart'
    if (dart.library.js_interop) 'room_notification_dismiss_web.dart';
