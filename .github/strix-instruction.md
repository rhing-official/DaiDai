# DaiDai のセキュリティスキャンの指示

DaiDai は、メールアドレス・電話番号・位置情報を集めない、Flutter（Web・Android・デスクトップ）＋Firebase（Firestore・Storage・Cloud Functions・Auth）のメッセージアプリです。公開リポジトリのソースを静的に読んでください。本番のサービスへの接続・攻撃は不要です。

## 重点（優先して見る）
- `firestore.rules`・`storage.rules`: 認可の抜け・過剰な公開、`get`／`list`の区別、他人のデータの読み書き
- `functions/src/`（Cloud Functions）: 認証・認可の確認漏れ（`onCall`の`request.auth`、管理者クレーム）、入力検証、Stripe Webhookの署名検証、アカウント削除・停止・管理者機能、パスキー（WebAuthn）・QRコードログイン・2段階認証・複数アカウント切り替えの認証フロー
- `lib/repositories/`（Firestore・Functionsを呼ぶ層）、`lib/repositories/auth_repository.dart`
- `cloudflare/worker.js`（OGP・認証の中継）

## 除外（見なくてよい）
- `third_party/`（外部ライブラリのコピー）、`build/`、`.dart_tool/`、`ios/`、`macos/`、`windows/`、`linux/`、`test/`、`lib/features/`の画面（UI）、画像・フォント等のアセット

## 設計として許容している点（指摘は不要。ただし、これ以外の使い方につながる場合は指摘する）
- Firebase のクライアント側 API キー・`google-services.json`・`firebase_options.dart`（公開前提の値）
- `stickerPacks`・`stickerRoles`・`creatorProfiles`の公開読み取り（daidai 横丁のカタログ表示のため）
- `users`コレクションを、ログイン済みの全ユーザーが読めること（運営の閲覧は監査ログで事後検証する設計）
- 広場のロールの権限を付けられる人が、実質的に全権限を渡せること（昇格防止は未実装）
- `userInvites`・`groupInvites`・`qrLoginSessions`の1件の取得（`get`）の公開（IDを知っている人だけが読める設計。一覧は禁止）

## 報告
- 深刻度の高い順に、再現の手順（どのファイルのどの条件で、何ができるか）と、修正案を書いてください。
