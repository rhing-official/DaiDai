// Web版プッシュ通知（FCM）用のService Worker（2026-08-31追加）。
// `flutter build web`は`web/`直下をそのまま`build/web/`へコピーするため、
// 追加のビルド設定無しでVercelにもデプロイされる。
//
// `lib/firebase_options.dart`のweb向け設定値と一致させること（apiKey等は
// Firebase Web SDKの性質上クライアントに公開される値であり秘匿情報ではない）。
importScripts(
  "https://www.gstatic.com/firebasejs/10.14.1/firebase-app-compat.js",
);
importScripts(
  "https://www.gstatic.com/firebasejs/10.14.1/firebase-messaging-compat.js",
);

firebase.initializeApp({
  apiKey: "AIzaSyAuX1o4MrRfacN4sQ_TMYrMl7PZXydQni4",
  appId: "1:380243513330:web:13d8bb20cd82bace0e656b",
  messagingSenderId: "380243513330",
  projectId: "daidai-rhing",
  authDomain: "daidai-rhing.firebaseapp.com",
  storageBucket: "daidai-rhing.firebasestorage.app",
});

const messaging = firebase.messaging();

// Cloud Functions（functions/src/pushNotifications.ts）はWebトークン向けに
// `webpush.notification`を積んで送信するため、FCM側が自動で表示する
// （このハンドラは基本的にログ目的のみで、明示的なshowNotificationは
// 呼ばない。二重表示を避けるため）。
messaging.onBackgroundMessage((payload) => {
  console.log("[firebase-messaging-sw.js] background message", payload);
});

// 通知タップ時、該当の語らいへのディープリンクURLを組み立てて、
// DaiDaiの既に開いているタブがあればそれをフォーカスの上そのURLへ遷移させ、
// 無ければ新規タブで開く（2026-09-02追加）。`data`は
// `functions/src/index.ts`のsendMessageNotificationがwebpush通知と並べて
// 積んでおり、FCMが自動表示したNotificationの`.data`としてここから
// 参照できる。`app_router.dart`の`/chat/dm/:dmId`・`/chat/group/:groupId`
// （ID単体からDirectMessage/Groupを解決する新ルート）が受け口になる。
self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  const data = event.notification.data || {};
  const conversationId = data.conversationId;
  const roomId = data.roomId;
  let targetUrl = "/";
  if (conversationId) {
    targetUrl = data.isDm === "true"
      ? `/chat/dm/${conversationId}`
      : `/chat/group/${conversationId}`;
    if (roomId) targetUrl += `?roomId=${roomId}`;
  }
  event.waitUntil(
    clients.matchAll({ type: "window", includeUncontrolled: true }).then((windowClients) => {
      for (const client of windowClients) {
        if ("focus" in client) {
          client.focus();
          if ("navigate" in client) client.navigate(targetUrl);
          return;
        }
      }
      if (clients.openWindow) return clients.openWindow(targetUrl);
    }),
  );
});
