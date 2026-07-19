# DaiDai（ダイダイ）

運営: Rhing（屋号）畑中新 / Version 1.0 / 2026年

プライバシーファーストの国産メッセージアプリ。メールアドレス・電話番号・位置情報を一切収集せず、Google/Appleアカウントのみで利用できる。広告なし、クリエイター還元率91.4%を掲げる。

キャッチコピー: 「整う、守る、私に馴染む。DaiDai」

> 詳細な企画背景・マーケティング戦略は `/home/arata/Rhing/Obsidian-Rhing/DaiDai/DaiDai-企画書.md`、技術詳細は同ディレクトリの `DaiDai-技術仕様書.md` を参照。このCLAUDE.mdは実装時に必要な要点のみをまとめたもの。

## Git管理

このディレクトリ（`/home/arata/Rhing/Applications/DaiDai`）自体が独立したgitリポジトリのルート。上位の`/home/arata/Rhing`ディレクトリとは別管理。

- リモート: `https://github.com/rhing-official/DaiDai`（private）
- デフォルトブランチ: `main`
- `日記.md`（`/diary`スキルで生成）の更新は確認なしで即座にpushする運用（詳細は`.claude/skills/diary/SKILL.md`）。それ以外の通常のコード変更のpushは都度確認を取ること。

## 技術スタック

| カテゴリ | 技術 |
|---------|------|
| フロントエンド | Flutter（iOS / Android / Windows / Linux / Web 統一） |
| 状態管理 | Riverpod |
| バックエンド（初期） | Firebase（Firestore / Storage / Functions / FCM / Auth） |
| バックエンド（将来） | Firebase → Supabase/Appwrite → 自前バックエンドへ段階移行 |
| 通話 | WebRTC（flutter_webrtc）、シグナリングはFirestore、STUNのみ（TURNはフェーズ1未導入） |
| 画像圧縮 | flutter_image_compress（WebP出力） |
| 決済 | Stripe + Webhook（ブラウザ決済のみ、アプリ内課金は不使用） |
| E2E暗号化（フェーズ2） | Signal Protocol。**自作せず既存の実装済みライブラリを使うこと**（詳細下記） |
| セキュアストレージ | flutter_secure_storage（秘密鍵保存） |
| CI/CD | GitHub Actions |
| 監視 | Firebase Analytics + Sentry |

### アーキテクチャ方針

バックエンドをFirebase→他へ段階移行する計画のため、**全レイヤーをRepositoryパターンで抽象化**し、実装を差し替え可能にする。

```dart
abstract class UserRepository {
  Future<User> getUser(String userId);
  Future<void> updateUser(User user);
}

class FirebaseUserRepository implements UserRepository {
  @override
  Future<User> getUser(String userId) async {
    final doc = await FirebaseFirestore.instance.collection('users').doc(userId).get();
    return User.fromJson(doc.data()!);
  }
}
```

新規のFirebase依存コードは必ずRepositoryインターフェース越しに書くこと。UIやビジネスロジックからFirestore SDKを直接叩かない。

### 暗号実装の方針

「Don't roll your own crypto」が鉄則。数式やアルゴリズムを自作せず、検証済みライブラリ・プロトコルを組み合わせる。
- 暗号ライブラリ（部品）: Web Crypto API / libsodium / Google Tink
- 暗号プロトコル（設計図）: Signal Protocol（E2EE全体の鍵管理・オフライン受信・端末紛失時の鍵失効などの手順まで含めて実装済み）
- E2E暗号化はフェーズ2実装。**専門家のセキュリティレビューが必須**（未レビューのまま本番投入しない）

## 独自用語（コード内の命名にも反映すること）

DaiDaiは独自の世界観用語を使う。変数名・クラス名・コレクション名を検討する際はこの対応を踏まえる（データモデルのフィールド名は英語だが、UI文言・概念名としてこれらを使う）。

| DaiDai独自 | LINE風 | Discord風 | 説明 |
|-----------|--------|----------|------|
| 語らい | トーク | チャンネル | メッセージのやり取りをする場所全般 |
| 住人 | ユーザー | メンバー | アプリを使う人 |
| 縁側 | 個人トーク | DM | 1対1の会話空間 |
| 広場 | グループ | サーバー | 3人以上のグループチャット |
| お部屋 | （なし） | チャンネル | 広場内の実際に会話する場所 |
| 節（ふし） | （なし） | カテゴリ | お部屋・席をまとめる区切り |
| 席（せき） | （なし） | スレッド | 縁側内のトピック別会話（フェーズ3） |
| 極み | プレミアム | Nitro | 有料サブスクリプションプラン（¥300/月） |
| ペタピタ | スタンプ | スタンプ | スタンプ機能 |
| 身だしなみ | プロフィール | プロフィール | プロフィール設定 |
| 蔵（くら） | アルバム | ギャラリー | プロフィール素材の保管場所 |
| ステメ | ひとこと | カスタムステータス | ステータスメッセージ |
| 便り | 公式アカウント | （なし） | 公式アカウント（拡張機能・将来検討） |
| 長（ちょう） | 管理者 | オーナー | 広場の管理者 |
| Sudachi | ファイル送信 | ファイル共有 | P2P直接ファイル転送（2GB超・無制限） |

アプリ設定でこの独自用語／LINE風／Discord風を切り替え可能にする仕様（`preferences.terminology`）がある。UI文言はハードコードせず切り替え可能な構造にする。

## データモデル（Firestore）概要

- **User**: `userId`, `rhingId`, `secretQuestions`（bcryptハッシュ）, `twoFactorEnabled`, `passkeyEnabled`, `deviceIds`, `bannedDevices`, `accountStatus`, `subscriptionPlan`(free|kiwami), `profiles[]`（最大3プロフィール＝蔵システム）, `preferences`
- **DirectMessage（縁側）**: `dmId`, `participants[2]`, `settings.sectionEnabled`, `sections[]`
- **Seat（席・フェーズ3）**: `seatId`, `dmId`, `sectionId`
- **Group（広場）**: `groupId`, `isPublic`, `requiresApproval`, `ownerId`, `moderators[]`, `members[]`（role: owner|moderator|member）, `sections[]`
- **Room（お部屋）**: `roomId`, `groupId`, `sectionId`, `permissions`
- **Message**: `conversationId`, `conversationType`(dm|seat|room), `contentType`(text|image|file|sticker|video), `fileMetadata.compressionType`(webp|lossless|raw), `readBy[]`, `deletedAt`（論理削除・選択的範囲削除）, `isSpam`
- 他: Sticker（ペタピタ）, Purchase（Stripe連携）, SafetyCheck（安否確認）, CustomRole, Album, VideoCall

詳細なフィールド定義・実装コード例は技術仕様書を参照。

## 重要な仕様・制約

- **Rhing ID**: 英数字・`.`・`-`・`_`のみ、筆記体不可、大文字小文字区別なし、重複不可、削除後再利用不可
- **パスワード復旧**: バックアップコードではなく秘密の質問3つ（bcryptハッシュ化）を採用。理由: 国民的インフラを見据えるとコード紛失対応コストが高いため
- **2段階認証**: TOTP（認証アプリのみ）、SMS非対応。フェーズ2
- **既読管理**: 極みプランで既読の一部/完全非表示が可能。完全非表示は「お部屋に1人でも極みプラン加入者がいれば全員に適用」という設計（個人単位の機能ではない点に注意）
- **1080pビデオ通話**: 同上、参加者1人でも極みプラン加入者がいれば通話全体が1080p化
- **画像保存期間**: 標準（WebP非可逆）は語らい内2週間・アルバム永久。高画質（極み・可逆/RAW）は語らい内1週間・1週間後にWebP変換
- **ファイル転送**: 2GBまでサーバー経由、超過分はSudachi（P2P、サーバー保存なし）
- **メッセージ削除**: 物理削除ではなく`deletedAt`による論理削除。範囲選択削除に対応（一括全削除UIは提供しない）
- **決済**: Stripe経由のブラウザ決済のみ。iOS/Android/macOSアプリ内課金は実装しない（プラットフォーム規約対応、審査説明文は企画書7章参照）
- **スパム対策**: 仲間承認制がベース。E2E暗号化との両立のためメッセージ内容はサーバー側で監視せず、メタデータ分析＋クライアント側チェックの多層防御（企画書/技術仕様書8章にレート制限の具体値あり）
- **安否確認（フェーズ3）**: 気象庁防災情報APIを1分ごとにポーリングし震度5強以上で発動。オプトイン方式、応答データは72時間後自動削除
- **削除アカウント情報**: 3時間以内に完全削除

## 実装しない機能（明確な方針）

以下は意図的に実装しない。関連する提案・実装依頼があっても踏襲しないこと。

| 機能 | 理由 |
|------|------|
| 広告表示 | ユーザー体験を損なう |
| 個人情報の収集・売却 | プライバシーポリシーに反する |
| メールアドレス・電話番号登録 | プライバシー重視 |
| DaiDai独自ポイント | 複雑化を避ける |
| マイナンバー連携 | 必要性がない |
| ダークモード | 極みプランへの誘導優先（10万人要望で再検討） |
| 着せ替え | DaiDai本来のUIを崩す恐れ |
| メーラー | 機能複雑化を避ける。作るなら別アプリ |
| Discordフォーラム機能 | 会話が細分化されすぎる懸念 |

## 開発フェーズ

| フェーズ | 目標DL | 主要実装内容 |
|---------|--------|-------------|
| フェーズ1（MVP・6ヶ月） | 10,000 | Google/Apple認証、Rhing ID、縁側・広場、720pビデオ通話、WebP圧縮、基本スパム対策。**E2E暗号化・極みプラン・ペタピタ・1080p通話は含めない** |
| フェーズ2（拡充・12ヶ月） | 100,000 | 極みプラン、ペタピタ・daidai横丁、E2E暗号化（Signal Protocol）、2段階認証、パスキー、QRコードログイン |
| フェーズ3（高度化・24ヶ月） | 1,000,000 | 公開広場、安否確認、ロール管理、節・席機能、方言対応、RNNoise |
| フェーズ4（将来） | 未定 | AI搭載メッセージ整理、ペタピタ作成アプリ（別アプリ）、貼プラン |

現在フェーズ1着手前（プロジェクトディレクトリは空）。実装時はこの順序を尊重し、後続フェーズの機能を先取りして作り込まない。

## デザイン

- メインカラー: 橙色 `#EE7800`。無料版カラーパレット・極みプラン限定カラー/フォントは技術仕様書11章参照
- 和紙に色が染み込むようなグラフィック、メッセージが横から「シュポン」と飛び出る演出（凝ったグラフィックはデザイナー雇用後）
- 無料版フォント: BIZ UDPMincho, BIZ UDGothic, チカラヅヨク, チカラヨワク

## Sumomoとの関係

Sumomo（別プロダクト、公的機関向け）とDaiDaiは完全に別サーバーで運用。SumomoからDaiDai/Rhingの情報を参照することは不可（実装上もデータ・インフラを混在させない）。
