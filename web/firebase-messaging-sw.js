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

// 通知タップ時、DaiDaiの既に開いているタブがあればそれをフォーカスし、
// 無ければ新規タブでルート（語らい一覧）を開く。特定の会話への
// ディープリンクは今回未対応（go_routerの/chat/dm・/chat/groupがURL単体
// ではなくextra引数でDirectMessage/Group全体を渡す設計のため、
// Service Worker側だけでは会話を復元できない）。
self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  event.waitUntil(
    clients.matchAll({ type: "window", includeUncontrolled: true }).then((windowClients) => {
      for (const client of windowClients) {
        if ("focus" in client) return client.focus();
      }
      if (clients.openWindow) return clients.openWindow("/");
    }),
  );
});
