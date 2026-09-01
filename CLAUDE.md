# DaiDai（ダイダイ）

  

運営: Rhing（屋号）畑中新 / Version 1.0 / 2026年

  

プライバシーファーストの国産メッセージアプリ。メールアドレス・電話番号・位置情報を一切収集せず、Google/Appleアカウントのみで利用できる。広告なし、クリエイター還元率91.4%を掲げる。

  

キャッチコピー: 「整う、守る、私に馴染む。DaiDai」

  

返答は日本語

  

> 企画・仕様の一次情報は `docs/`（`/home/arata/Rhing/Obsidian-Rhing/DaiDai/` のMarkdownへのシンボリックリンク、git管理外）を参照。実装方針に迷ったとき・新機能に着手する前には必ず目を通すこと。

> - `docs/DaiDai-企画書.md`: 企画背景・マーケティング戦略

> - `docs/DaiDai-技術仕様書.md`: 技術仕様の詳細

> - `docs/マップ.md`: 最新のサイトマップ・画面構成・用語検討

>

> このCLAUDE.mdは実装時に必要な要点をその時点でまとめたものであり、`docs/`側が更新される都度、内容が古くなりうる。用語表は`docs/マップ.md`（2026-07-20時点の内容）を反映済み（「独自用語」節参照）だが、Obsidian側は継続的に検討中のため、今後もズレが生じうる。**このCLAUDE.mdとdocs/の内容が食い違う場合は、どちらに合わせるべきかユーザーに確認してから進めること**（無断でどちらかに決め打ちしない）。

  

## Git管理

  

このディレクトリ（`/home/arata/Rhing/Applications/DaiDai`）自体が独立したgitリポジトリのルート。上位の`/home/arata/Rhing`ディレクトリとは別管理。

  

- リモート: `https://github.com/rhing-official/DaiDai`（private）

- デフォルトブランチ: `main`

- `/diary`実行時は、`日記.md`の更新に加えてその時点のFlutterプロジェクト一式の変更（`lib/`, `android/`, `ios/`等リポジトリ全体）も含めて確認なしで即座にpushする運用（詳細は`.claude/skills/diary/SKILL.md`）。`/diary`を経由しない通常のコード変更のpushは、これまで通り都度確認を取ること。

  

## アカウント管理

  

DaiDai関連でブラウザ操作・ログインが必要な場面（Firebase Console、Google Cloud Console、Google Play Consoleなど）では、個人アカウント（arataurusu@gmail.com）ではなく **`rhing.official@gmail.com`** でログインすること。GitHubの`rhing-official`組織アカウントと同様、Rhing名義の作業は専用アカウントに統一する。

  

- Firebaseプロジェクトはこのアカウント（`rhing.official@gmail.com`）で作成済み

- Firebase CLI / gcloud CLIなどのツールでログインする際も同アカウントを使う

  

## 開発時の動作確認（2026-07-22追加、2026-08-02更新）

  

- **実装が完了しても、動作確認用の環境（`flutter run -d web-server --web-port=8765`等）を自動的に立ち上げる必要は無い**。動作確認は基本的にユーザー自身が行う。`flutter analyze`・`flutter test`・`dart format`等コード上で完結する検証までを実装完了の基準とする

- 既に環境を起動済みで作業中の流れの中でコードを変更した場合は、後述のホットリロード対応を続けて構わない（新規に起動し直すことと、起動済みのものへ変更を反映することは別）

- ユーザーから「起動して」「もう一度開いて」等、明示的に起動を求める指示があった場合は、方針確認などを挟まず即座に起動作業に入ること

- **デバッグ中に更にコードを変更した場合は、その都度ホットリロード（`r`）／ホットリスタート（`R`）を確認を挟まず実行し、変更を反映させること**。`main()`やRiverpodの`ProviderScope`の初期化（override）を変更した場合、または新規パッケージを追加した場合はホットリロードでは反映されないため`R`（ホットリスタート）を使う。それでも反映されない場合（新規パッケージ追加直後など）は`flutter run`プロセスを完全に再起動する

- `flutter run`をこちら側でバックグラウンド起動している場合、ユーザーの端末からは`r`/`R`のキー入力を送れない（別プロセスのため）。その場合は対象プロセスのPIDに`kill -SIGUSR1 <pid>`（ホットリロード）／`kill -SIGUSR2 <pid>`（ホットリスタート）でシグナルを送ることで代替できる

  

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

  

DaiDaiは独自の世界観用語を使う。変数名・クラス名・コレクション名を検討する際はこの対応を踏まえる（データモデルのフィールド名は英語だが、UI文言・概念名としてこれらを使う）。`docs/マップ.md`の用語検討を反映した最新版（2026-07-20更新）。

  

| DaiDai独自（世界観重視） | 利便性重視 | Discord風 | 説明 |

|-----------|--------|----------|------|

| 語らい | トーク | チャンネル | メッセージのやり取りをする場所全般 |

| 住人 | ユーザー | メンバー | アプリを使う人 |

| 一対（いっつい） | ダイレクト | DM | 1対1の会話空間（**旧称: 縁側**） |

| 広場 | サーバー・コミュニティ | サーバー | 3人以上のグループ全体の場 |

| 表広場 | 公開サーバー | Public Server | 不特定多数が参加できる公開の広場（フェーズ3） |

| 裏広場 | 非公開サーバー | Private Server | 友人のみの非公開の広場（フェーズ1のデフォルトはこちら） |

| 寄合（よりあい） | チャンネル | Text Channel | 広場内の通常の会話の場（**旧称: お部屋**） |

| 密談 | 非公開チャンネル | Private Channel | 広場内の非公開の会話の場 |

| 表組 | カテゴリ | Category | 寄合・密談をまとめる通常の区切り（**旧称: 節**） |

| 裏組 | 非公開カテゴリ | Private Category | 非公開の区切り |

| 談論 | プロジェクトボード | Project Board | 目的達成・進行型のフォーラム。※下記「実装しない機能」表のDiscordフォーラム機能と概念が重なるため要確認 |

| 席（せき） | スレッド | Thread | 一対内のトピック別会話（フェーズ3構想だったが、2026-07-28にユーザー判断で前倒し、「席」ではなく広場と同じ「寄合」の呼称のまま一対にも複数会話機能として実装済み。「席」という用語自体は未使用のまま残す） |

| 極み | プレミアム | Nitro | 有料サブスクリプションプラン（¥300/月） |

| ペタピタ | スタンプ | スタンプ | スタンプ機能 |

| 身だしなみ | プロフィール | プロフィール | プロフィール設定 |

| 蔵（くら） | マテリアルボックス | ギャラリー | プロフィール素材の保管場所 |

| 工房 | プロフィール作成 | Profile Creator | 複数プロフィール（蔵）の作成・編集画面 |

| 一言 | ステータスメッセージ | カスタムステータス | ステータスメッセージ（**旧称: ステメ**、2026-07-24変更） |

| 呼び名 | ニックネーム | ニックネーム | 友達に表示する呼び名（2026-07-24追加） |

| 便り | 公式アカウント | （なし） | 公式アカウント（2026-08-12実装済み、下記「運営向け管理画面」参照。「将来検討」だったが管理画面のお知らせ配信機能とあわせて前倒し実装した） |

| 長（ちょう） | 管理者 | オーナー | 広場の管理者 |

| Sudachi | ファイル送信 | ファイル共有 | P2P直接ファイル転送（2GB超・無制限） |

| 縁結び | フレンド追加 | フレンド追加 | 招待リンク・QRコードで友達を追加する画面（2026-07-24追加） |

  

アプリ設定で用語セット（世界観重視／利便性重視）を切り替え可能にする仕様は2026-07-24に実装したが、2026-08-13に廃止し世界観重視の用語へ一本化した（理由: 言語・用語設定の組み合わせによって画面上のブロックの大きさが変わり、全画面での対応が困難になったため）。`lib/l10n/vocabulary.dart`の`Vocabulary`クラスは表示言語（`AppLocale`、日本語／English）のみを軸とする対訳セット（`Vocabulary.japanese`/`Vocabulary.english`）に縮小し、`TerminologyStyle`・`terminologyStyleProvider`・設定タブの「用語・表示設定」セクションは削除済み（`preferences.terminologyStyle`もクライアント側では書き込まなくなったが、Firestore上の既存データはマイグレーションしていない）。UI文言は`vocabularyProvider`経由で取得し、蔵/工房・一対/広場・呼び名（ニックネーム）・一言（ステメ）等の呼称に反映済み（それ以外の画面文言は`Strings`クラスで別途ロケール切り替えのみ対応。ただしニックネーム/ステメ関連の一部の文言は`String Function(String term)`型のフィールドにして用語を差し込んでいる。Englishは日本語の世界観重視用語に相当する固定訳のみ提供）。蔵のニックネーム・ステメ一覧からは「使うものを選ぶ」ラジオ選択機能を廃止し（2026-07-24）、表示に使う1件は登録順で自動的に決まる。

  

> `docs/マップ.md`と本ファイル本文の間にあった食い違い3点は、2026-07-24にユーザー確認の上で解消した:

> 1. **談論（プロジェクトボード型フォーラム）**: マップ.md通りに広場の詳細画面（`lib/features/chat/plaza_detail_dialog.dart`）へ準備中項目として追加した。「実装しない機能」表の「Discordフォーラム機能」とは別物として扱う（実際のフォーラム機能自体は未実装のまま）。

> 2. **バックアップコード**: 追加しない方針を維持（不採用）。設定画面にも項目を出さない。

> 3. **メールアドレス**: 追加しない方針を維持（不採用）。設定画面にも項目を出さない。

  

> **既存コードへの影響**: 現在の実装（`lib/`）はまだ旧称（`DirectMessage`クラス・`directMessages`コレクション・UI文言「縁側」など）のままになっている。上記の新用語を正式採用する場合、コード側のリネームは別タスクとして扱うこと（このドキュメント更新だけでは自動的に反映されない）。

  

## データモデル（Firestore）概要

  

- **User**: `userId`, `rhingId`, `deviceIds`, `bannedDevices`, `accountStatus`(active|pendingDeletion|suspended、suspendedは2026-08-12追加。運営向け管理画面からの手動停止のみで、技術仕様書8.4の期限付き自動停止とは連携しない), `createdAt`/`lastLoginAt`（2026-08-12追加、管理画面向け。`lastLoginAt`は認証済みセッション確認のたびに更新するため「最終アプリ起動日時」に近い）, `subscriptionPlan`(free|kiwami), `profiles[]`（最大3プロフィール＝蔵システム）, `preferences`。2段階認証の有効/無効はFirestoreに複製せずFirebase Authenticationの登録済み要素を都度参照する設計にしたため、旧`twoFactorEnabled`という想定フィールドは不要と判明した（2026-08-09、下記「ログイン手段の方針」参照）。`secretQuestions`（bcryptハッシュ）・`passkeyEnabled`は将来のRhing ID＋パスキー導入時のための想定フィールドで、現時点では未実装

- **DirectMessage（一対）**: `dmId`, `participants[2]`, `defaultRoomId`, `settings.sectionEnabled`, `sections[]`。メッセージは`directMessages/{dmId}/rooms/{roomId}/messages`（複数寄合対応、2026-07-28実装）に入る。寄合自体は`directMessages/{dmId}/rooms/{roomId}`（`DmRoom`: `dmId`, `name`, `participants[]`, `createdAt`, `deletionRequestedBy`）。参加者2人はどちらも寄合の追加・削除が可能（確認無しで追加、削除は確認ダイアログあり、最後の1つは削除不可）

- **Group（広場）**: `groupId`, `isPublic`（表広場/裏広場の区別）, `requiresApproval`, `ownerId`（長、常に全権限を持ち譲渡可能、2026-07-28更新）, `memberRoles`（役職の表示・退会時クリーンアップ用に構造は残すが、`moderator`は権限判定には使わず`GroupPermission`ベースのカスタムロールに統合済み）, `defaultRoomId`, `sections[]`（表組/裏組）, `roleAssignments`（userId→GroupRole.roleIdのリスト、複数付与可、2026-07-28更新）, `rolePriority`（ロールidの並び、呼び名の色の優先順位）, `memberPermissions`（userId→有効な権限文字列のリスト、firestore.rules用に非正規化したキャッシュ）

- **Room（寄合・密談）**: `roomId`, `groupId`, `name`, `memberIds`, `createdAt`, `roomDeletionRequestedBy`（寄合＝公開・密談＝非公開の区別は要検討）。1つの広場に複数作成可能（2026-07-28実装）。追加・削除は`manageRooms`権限を持つメンバーのみ。`rolePriorityOverride`（この寄合限定でのロール優先順位の上書き、nullなら広場全体の`Group.rolePriority`を使う、2026-07-28更新）

- **GroupRole（`groups/{groupId}/roles/{roleId}`）**: `roleId`, `groupId`, `name`, `color`(0xRRGGBB、nullable), `permissions`（`GroupPermission`の部分集合: manageRooms/manageRoles/manageReadReceipts/manageJoinRequests/createInvite）, `isEveryone`（全メンバーに自動適用される削除・改名不可の基準ロール、広場に1件）, `createdAt`。広場のカスタムロール（2026-07-28実装、権限・複数付与対応版）。作成・編集・削除・メンバーへの付与は`manageRoles`権限を持つメンバーのみ。メッセージ画面のアイコン横の呼び名のフォントカラーにも反映される

- **Message**: `conversationId`, `conversationType`(dm|seat|room), `contentType`(text|image|file|sticker|video), `fileMetadata.compressionType`(webp|lossless|raw), `readBy[]`, `hiddenFor[]`（範囲選択削除・本人のuserIdを追加するだけの個人単位の非表示）, `isSpam`

- 他: Sticker（ペタピタ）, Purchase（Stripe連携）, SafetyCheck（安否確認）, Album, VideoCall

  

詳細なフィールド定義・実装コード例は技術仕様書を参照。

  

## 重要な仕様・制約

  

- **Rhing ID**: 英数字・`.`・`-`・`_`のみ、筆記体不可、大文字小文字区別なし、重複不可、削除後再利用不可

- **ログイン手段の方針（2026-08-09決定）**: Google/Apple OAuthのみを採用し、DaiDai独自のRhing ID＋パスワードは新設しない。理由: (1) パスワード運用（忘れた場合の復旧対応・漏洩対策）のサポート負担を避けられる、(2) Google/Appleにログインできない場合の対応はこちらの管轄外にできる、(3) 日本国内でもGoogleアカウント保有率は十分高く、ログイン手段がGoogleのみであること自体が導入の障壁にはなりにくい。この決定に伴い、DaiDai独自のパスキー（WebAuthn）実装も現時点では不要と判断した: DaiDaiは認証情報を一切保持せずGoogle/Appleに完全委任しているため、パスキーが本来置き換える対象（DaiDai自身が持つ認証情報）が存在しない。またFirebaseのMFA機構（下記2段階認証）はパスキーを第2要素として認識しないため、「パスキーでログインすれば2段階認証を省略できる」という設計も現行アーキテクチャでは成立しない。
  - **将来の検討事項（未着手・未決定）**: プライバシーファーストを掲げる以上、Google/Appleへの依存自体が長期的には理念と緊張関係にある（サインイン時にGoogle/Apple側にDaiDai利用の事実が伝わる、アカウント停止時の依存リスクなど）。「国民的インフラ」を見据えて将来Google/Apple非依存のログイン手段が必要になった場合は、メールアドレス＋パスワードではなく**「Rhing ID＋パスキー」**（メールアドレス不要、DaiDai自身がWebAuthnのRelying Partyになる）を軸に検討する方針とする。これはDaiDai自身が独立した認証基盤を持つことを意味し、フェーズ2の軽微な追加機能ではなく設計判断として改めて相談してから着手する。`secretQuestions`（bcryptハッシュ、データモデル参照）は、この将来のパスキー方式導入時の「端末紛失時のアカウント復旧」用フィールドとして温存しているが、現行のGoogle/Apple OAuthのみの構成では未使用・未実装

- **2段階認証（TOTP、2026-08-09実装済み）**: 認証アプリのみ対応、SMS非対応。Firebase AuthenticationのMulti-Factor Authentication機能を使用（`lib/repositories/auth_repository.dart`のTOTP関連メソッド、登録ダイアログ`lib/features/auth/two_factor_setup_dialog.dart`、サインイン時チャレンジUIは`lib/features/auth/sign_in_screen.dart`）。Firebase ConsoleのUIにはTOTPを有効化するトグルが無く、Identity Platformへのアップグレード後、Admin SDK/REST APIでのプロジェクト設定変更が別途必要だった（一度きりのCloud Functions経由で実行、実行後にソースから削除済み）。フェーズ2計画だったが前倒しで実装済み

- **既読管理**: 極みプランで既読の一部/完全非表示が可能。完全非表示は「寄合に1人でも極みプラン加入者がいれば全員に適用」という設計（個人単位の機能ではない点に注意）

- **1080pビデオ通話**: 同上、参加者1人でも極みプラン加入者がいれば通話全体が1080p化

- **画像保存期間**: 標準（WebP非可逆）は語らい内2週間・アルバム永久。高画質（極み・可逆/RAW）は語らい内1週間・1週間後にWebP変換

- **ファイル転送**: 2GBまでサーバー経由、超過分はSudachi（P2P、サーバー保存なし）

- **メッセージ削除（2026-07-27実装）**: 一対・広場どちらも、複数選択（連続していなくてもよい）した範囲を削除できる（一括全削除UIは提供しない）。削除は本人のアカウントから見えなくするだけで、実際にはサーバーから消えず他の参加者には引き続き見える（`Message.hiddenFor`に自分のuserIdを追加）。その語らいの参加者**全員**が同じメッセージを削除し終えた時点で、その操作を行ったクライアントがサーバーからも物理削除する（`DirectMessageRepository.hideMessagesForMe`/`GroupRepository.hideRoomMessagesForMe`、firestore.rulesで「自分を加えたら全員揃うか」を検証してから物理削除を許可）

- **決済**: Stripe経由のブラウザ決済のみ。iOS/Android/macOSアプリ内課金は実装しない（プラットフォーム規約対応、審査説明文は企画書7章参照）

- **スパム対策**: 友達承認制がベース。E2E暗号化との両立のためメッセージ内容はサーバー側で監視せず、メタデータ分析＋クライアント側チェックの多層防御（企画書/技術仕様書8章にレート制限の具体値あり）

- **安否確認（フェーズ3）**: 気象庁防災情報APIを1分ごとにポーリングし震度5強以上で発動。オプトイン方式、応答データは72時間後自動削除

- **アカウント削除（2026-07-28実装、旧: 3時間以内に完全削除から変更）**: 設定＞アカウントから2パターン選べる。(1) **通常削除**（`UserRepository.requestAccountDeletion`）: 申請後30日間は情報を保持し、その間にログインすると「アカウントを復元しますか？」（`lib/features/auth/account_restore_screen.dart`）から復元できる。何も操作をしないまま31日目の00:00（Asia/Tokyo）になると、Cloud Functions（`functions/src/index.ts`の`processAccountDeletions`、毎日00:00実行のスケジュールトリガー）がサーバーから全情報を完全削除する。(2) **即時削除**（`UserRepository.deleteAccountImmediately`）: 30日間の猶予を経ず、Cloud Functionsのcallable関数`deleteAccountImmediately`（同ファイル、認証中の本人のみ呼び出し可）を通じてその場で完全削除する（復元不可）。どちらも実際の削除処理は共通の`deleteAccount`ヘルパーを使う（Firestore・Firebase Authとも削除）。一対（DM）には削除完了時点で「〇〇がアカウントを削除しました。語らいを削除しますか？」と通知され、「はい」→確認→即時に会話履歴を物理削除、「いいえ」なら通知だけが残る（`DirectMessage.accountDeletedUserId`、`Message.contentType == 'accountDeleted'`）。広場には「〇〇がアカウントを削除しました。」の通知のみで、削除の選択肢は無い。**長を務める広場が1件でも残っている間はアカウントを削除できない（2026-08-02実装）**: 通常削除・即時削除どちらの入り口でも、削除操作前に対象の広場一覧と「長を譲渡」導線（既存の`GroupMemberListPopup`を再利用）を出すガードダイアログ（`settings_tab.dart`の`_OwnerGroupsGuardDialog`）が挟まり、全ての広場で`GroupRepository.transferOwnership`により別のメンバーへ譲渡し終えるまで先へ進めない。Cloud Functions側にも同じ制約の安全策があり、`deleteAccountImmediately`は長を務める広場が残っていれば`failed-precondition`で拒否し、`processAccountDeletions`（30日後の自動削除）も実行直前に再チェックして残っていればその日は削除をスキップする（猶予期間中に新たに広場を作成・譲受した場合への対応）。この制約により、`notifyAndLeaveGroups`内の「長の場合は除去せず通知のみ」という分岐は実質到達しない防御的コードとして残っている

- **運営向け管理画面（2026-08-12実装）**: 住人一覧・アカウント停止/解除・便り（公式アカウント）からのお知らせ配信を行う、`/admin`という隠しルート（`lib/features/admin/`、`lib/router/app_router.dart`）。通常のナビゲーションからは導線を出さず、URLを直接開いた場合のみ到達する。
  - **管理者判定**: Firebase Custom Claims（`admin: true`）。DaiDaiはOAuth専用でメール・パスワード認証を持たないため、管理者専用の別ログインは作らず既存のDaiDaiアカウントにクレームを付与する。判定は`AuthRepository.isAdmin()`（IDトークンの`claims`を確認）・`isAdminProvider`（`lib/providers/repository_providers.dart`）。
  - **初回管理者登録**: Cloud Functionsのcallable関数`grantFirstAdminOnce`（`system/adminBootstrap`ドキュメントの`consumed`フラグをトランザクションで確認し、最初に呼んだ人だけが管理者になれる「早い者勝ち」のブートストラップ）。`/admin`を非管理者で開くと表示される「初回管理者として登録」ボタンから、CLIを使わずアプリのUIだけで完結する。他の一度きりのCloud Functionsスクリプト（TOTP有効化等）と同じ「実行後にソースから削除」パターンを踏襲する想定だが、2026-08-12時点では運営本人によるデプロイ・実行・確認がまだ済んでおらず、関数はソースに残っている（確認が取れ次第、削除・`firebase functions:delete`での後始末を行う）。
  - **アカウント停止**: `AccountStatus.suspended`（シンプルな手動停止/解除のみ、技術仕様書8.4の期限付き自動停止とは連携しない）。Cloud Functionsのcallable関数`suspendUserAccount`（管理者クレームを確認した上で`accountStatus`を更新し、停止時は`revokeRefreshTokens`で既存セッションも即座に無効化）。停止中のアカウントは`AuthGate`が`AccountSuspendedScreen`（`lib/features/auth/account_suspended_screen.dart`）を表示し、`pendingDeletion`と違い自己解除の手段は無い（管理者のみが解除できる）。
  - **お知らせ配信（便り）**: Cloud Functionsのcallable関数`broadcastAnnouncement`。固定UID（`official-tayori`）の`users`ドキュメント（Firebase Authに対応する実アカウントは持たない）を便りとして用意し、稼働中（`accountStatus == active`）の全住人との一対に、通常の一対と同じスキーマ（`DirectMessage`/`DmRoom`/`Message`）でメッセージを書き込む。dmIdは`DirectMessage.idFor`と同じ決定的なpairId方式のため、2回目以降の配信も同じ一対の続きとして届く。
  - Firestoreルールの変更は無し（住人一覧の読み取りは既存の全ログイン済みユーザー向け`users`読み取りルールで賄え、停止・配信はAdmin SDK経由でルールを経由しないため）。

## 実装しない機能（明確な方針）

  

以下は意図的に実装しない。関連する提案・実装依頼があっても踏襲しないこと。

  

| 機能 | 理由 |

|------|------|

| 広告表示 | ユーザー体験を損なう |

| 個人情報の収集・売却 | プライバシーポリシーに反する |

| メールアドレス・電話番号登録 | プライバシー重視 |

| DaiDai独自ポイント | 複雑化を避ける |

| マイナンバー連携 | 必要性がない |

| 着せ替え | DaiDai本来のUIを崩す恐れ |

| メーラー | 機能複雑化を避ける。作るなら別アプリ |

| Discordフォーラム機能 | 会話が細分化されすぎる懸念（※`docs/マップ.md`の「談論」構想と重複。方針要確認、上記「独自用語」節参照） |

  

## 開発フェーズ

  

| フェーズ | 目標DL | 主要実装内容 |

|---------|--------|-------------|

| フェーズ1（MVP・6ヶ月） | 10,000 | Google/Apple認証、Rhing ID、一対・広場（既定は裏広場）、720pビデオ通話、WebP圧縮、基本スパム対策。**E2E暗号化・極みプラン・ペタピタ・1080p通話は含めない** |

| フェーズ2（拡充・12ヶ月） | 100,000 | 極みプラン、ペタピタ・daidai横丁、E2E暗号化（Signal Protocol）、QRコードログイン。**2段階認証（TOTP）は2026-08-09に前倒し実装済み。パスキーは同日の方針決定によりフェーズ2の実装対象から除外（不採用ではなく将来の検討事項、上記「ログイン手段の方針」参照）** |

| フェーズ3（高度化・24ヶ月） | 1,000,000 | 表広場（公開広場）、安否確認、表組・裏組、方言対応、RNNoise。**一対の複数会話（席機能相当）・広場のカスタムロール機能は2026-07-28に前倒し実装済み（下記参照）** |

| フェーズ4（将来） | 未定 | AI搭載メッセージ整理、ペタピタ作成アプリ（別アプリ）、貼プラン |

  

### 広場のカスタムロール機能（2026-07-28実装、権限・複数付与対応版）

  

広場（グループ）にDiscordライクなカスタムロールを作れる。名前・色（呼び名のフォントカラーに反映）に加えて実際の**権限**を持ち、1人のメンバーに複数のロールを同時付与できる。既存の「長・モデレーター・メンバー」階層は廃止し、この仕組みに統合した:

  

- **長（`Group.ownerId`）**: 常に全権限を持つ特別な存在。広場作成者が初期値だが、メンバー一覧ポップアップから他のメンバーへ後から譲渡できる（`GroupRepository.transferOwnership`、firestore.rulesで現オーナーのみに強制）。譲渡後、旧オーナーは通常のメンバーになる。

- **カスタムロール（`groups/{groupId}/roles/{roleId}`、`GroupRole`）**: 名前・色（nullable、色を持たないロールも作れる）・権限（`GroupPermission`の部分集合）を持つ。DaiDaiに実在する5つの管理操作にのみ対応: `manageRooms`（寄合の管理）、`manageRoles`（ロールの管理）、`manageReadReceipts`（既読機能のオン/オフ）、`manageJoinRequests`（参加リクエストの承認・却下）、`createInvite`（招待リンクの作成）。Discordのボイスチャンネル・AutoMod等、DaiDaiに存在しない機能の権限は無い。

- **基準ロール（`GroupRole.isEveryone`）**: 広場作成時に自動生成される、全メンバーに暗黙適用される削除・名前変更不可のロール（Discordの`@everyone`相当）。デフォルトは`createInvite`のみ許可（招待リンク作成は元々誰でも可能だった挙動を再現）。

- **付与**: `Group.roleAssignments`（userId→ロールidのリスト、複数可）。`GroupRepository.assignRole`/`unassignRole`で個別に付与・解除する。

- **色の優先順位**: 複数ロールを持つメンバーの呼び名の色は、`Group.rolePriority`（ロールidの並び、先頭が最優先）で決まる。寄合ごとに`Room.rolePriorityOverride`で優先順位を上書きでき、設定されていれば広場全体の順序より優先される（寄合ハンバーガーメニューの「この寄合の色優先順位を設定」から、`lib/features/chat/group_role_priority_dialog.dart`の`GroupRolePriorityDialog`で`ReorderableListView`によるドラッグ＆ドロップ並べ替えを行う）。

- **実効権限のキャッシュ（`Group.memberPermissions`）**: firestore.rulesはロールドキュメントを跨いだ動的な権限計算ができないため、`lib/utils/group_permissions.dart`の`hasGroupPermission`が根拠にする`memberPermissions`（userId→有効な権限文字列のリスト、基準ロール込みで解決済み）を`GroupRepository`がロール・付与の変更のたびに再計算して非正規化保存する（`Room.memberIds`が`Group.memberIds`を非正規化して持つのと同じ設計）。firestore.rulesも同じフィールドを参照して判定するため、クライアントの計算結果をそのまま信頼する設計になっている点に注意（デプロイ済み）。

- UI: ハンバーガーメニューではなくサイドバー（寄合一覧ペイン`RoomListPane`）のヘッダーに歯車アイコン「広場自体の設定」を追加し、`manageRoles`権限を持つメンバーのみ`lib/features/chat/group_role_list_popup.dart`の`GroupRoleListPopup`（ロールのCRUD・権限チェックボックス・色のhex入力・優先順位並べ替え導線）を開ける。メンバーへの付与・長の譲渡はメンバー一覧ポップアップ（`group_member_list_screen.dart`）から行う。

- ロールの色は設定タブのアクセントカラーと同じ「`#RRGGBB`のカラーコードを自由入力」方式（`lib/utils/color_hex.dart`の`tryParseHexColor`/`ColorHex.toHexString`を再利用）。

- メッセージ画面（`lib/features/chat/chat_screen.dart`）の呼び名表示コンポーネント（`_SenderName`）に、色を解決するコールバック（`ChatScreen.senderNameColorResolver`）を追加。一対には常に渡さない（ロールが存在しないため）。`GroupChatPane`が`lib/utils/group_permissions.dart`の`resolveSenderColor`を使い、送信者ごとに色を解決する。

- 既存の本番データ（2広場）はCloud Functionsの一度きりの移行処理（`functions/src/index.ts`、実行後にソースから削除済み）で、基準ロールの作成と実効権限キャッシュの初期計算を行った（`memberRoles`が`moderator`のメンバーがいた場合は自動的に相当するロールへ変換する処理も含めたが、対象は0件だった）。

  

### 複数寄合機能（2026-07-28実装）

  

広場・一対どちらも、1つの会話の中に複数の「寄合」（テキストチャンネル）を作れる。広い画面（横表示）では、友達一覧・広場一覧のサイドバー（`lib/features/chat/talks_tab.dart`の分割表示）の右隣に、選択中の会話の寄合一覧サイドバー（`lib/features/chat/room_list_pane.dart`の`RoomListPane`）が表示され、そこから寄合の追加（確認無しで名前を入力してすぐ作成）・削除（「本当に削除しますか？」の確認あり、最後の1つは削除不可）ができる。狭い画面（縦表示）ではサイドバーを経由するフルスクリーンのドリルダウン画面は使わず、一覧で相手/広場をタップすると`defaultRoomId`で直接チャット画面（`/chat/dm`・`/chat/group`）へ1ステップで遷移し、寄合の切り替えはチャット画面のAppBar直下に表示される横スクロールタブバー（`lib/features/chat/room_tab_bar.dart`の`RoomTabBar`、寄合を選ぶと`pushReplacement`で画面ごと差し替える）から行う（2026-08-03変更、以前は`/chat/dm-rooms`・`/chat/group-rooms`ルート＝`room_list_screen.dart`のフルスクリーン寄合一覧を経由するドリルダウン構成だったが、当該ルート・ファイルとも削除した）。寄合の追加ボタンは`RoomTabBar`にも用意するが、削除・改名はサイドバー同様このバーからは行わずハンバーガーメニューから行う。単一モード（`roomsEnabled == false`）の会話ではどちらの画面幅でもこれらのUI自体を出さない。

  

- 広場側の寄合追加・削除は長・モデレーターのみ（firestore.rulesで強制）。既存の`GroupRepository`が元々`rooms`サブコレクション・`defaultRoomId`という複数ルーム前提の設計だったため、`watchRooms`/`createRoom`/`deleteRoom`を追加し、`respondToJoinRequest`/`leaveGroup`/`setReadReceiptsEnabled`をdefaultRoomId決め打ちから全room走査に修正する形で対応した。

- 一対側は参加者2人がどちらも対等に追加・削除できる（役割が無いため）。既存の`directMessages/{dmId}/messages`というフラット構造を、広場と同じ`directMessages/{dmId}/rooms/{roomId}/messages`構造に変更（`DirectMessage.defaultRoomId`追加、新規`lib/models/dm_room.dart`の`DmRoom`）。既存データはCloud Functionsの一度きりの移行処理（`functions/src/index.ts`、実行後にソースから削除済み）で新構造へ移した。

- 寄合の削除は、severance（絶縁）・既読オフと同じ「削除実行者を記録するマーカーフィールド（`roomDeletionRequestedBy`/`deletionRequestedBy`）を立ててからメッセージを物理削除し、最後に寄合自体を削除する」パターンで実装している。

- **重要な実装上の注意**: `GroupRepository.watchRooms`/`DirectMessageRepository.watchRooms`は、対象の`rooms`サブコレクションを`where('memberIds'/'participants', arrayContains: userId)`という絞り込み条件**付きで**クエリする必要がある（`userId`引数必須）。Firestoreの`list`操作は、クエリ自体にセキュリティルールと同じ条件の`where`句が無いと「返り得る全ドキュメントがルールを満たすと証明できない」として要求全体を`permission-denied`で拒否する仕様があり、絞り込み無しの単純な全件取得クエリではルール・データが正しくても寄合一覧が一切表示されなくなる（2026-07-28の複数寄合機能実装当初からこの不具合が入り込んでおり、2026-07-29に発覚・修正した）。

  

### 寄合の単一/複数モード（2026-07-29追加）

  

広場は作成時に、一対は常に、まず「単一モード」（`roomsEnabled: false`、寄合はdefaultRoomIdの1つだけ・サイドバー非表示・設定は全てハンバーガーメニューに格納）で始められる。広場作成画面（`create_group_screen.dart`）に「寄合を複数作成する」トグルがあり、オフを選ぶと単一モードになる。単一モードから複数モードへは、ハンバーガーメニューの「寄合を複数扱う」（広場、`manageRooms`権限が必要）・「寄合を増やす」（一対、参加者ならどちらでも）でいつでも切り替えられる（`Group.roomsEnabled`/`DirectMessage.roomsEnabled`、`GroupRepository.setRoomsEnabled`/`DirectMessageRepository.setRoomsEnabled`）。複数→単一に戻す機能は無い（firestore.rulesでも`true`への変更のみ許可）。この機能追加前に作られた既存の広場・一対は、フィールド欠落時のfromJsonデフォルト値により全て複数モード扱いになる（既存の複数寄合表示を維持するため）。

  

現在フェーズ1着手前（プロジェクトディレクトリは空）。実装時はこの順序を尊重し、後続フェーズの機能を先取りして作り込まない。

  

### プラットフォーム実装・リリース順序

  

各フェーズ内での実装・リリースの優先順位（2026-07-20決定）:

  

1. ブラウザ（Web）

2. Android

3. Windows

4. Linux

5. iOS

6. macOS

  

動作確認やビルド確認は基本的にこの順で行う。新機能を各プラットフォームに展開する際もこの優先度を踏襲する。

  

## デザイン

  

- メインカラー: 橙色 `#EE7800`。無料版カラーパレット・極みプラン限定カラー/フォントは技術仕様書11章参照

- 和紙に色が染み込むようなグラフィック、メッセージが横から「シュポン」と飛び出る演出（凝ったグラフィックはデザイナー雇用後）

- 無料版フォント: BIZ UDPMincho, BIZ UDGothic, チカラヅヨク, チカラヨワク

- ボタンの配色: 背景色が薄い（明度が高い）色に白色のテキストを乗せる組み合わせは禁止。コントラストが不十分で読みにくくなる（`colorScheme.error`はダークテーマ下のMaterial3仕様で明るいサーモンピンクに近い色になり白文字が読みにくくなる、2026-08-12の教訓）。削除確認等の警告色ボタンは固定の濃い赤（`Colors.red.shade700`等）など、実際にコントラストが確保できる色を明示的に指定すること。

- テキスト（フォント）にアクセントカラーを使わない。`TextButton`等の文字色はアクセントカラー（`colorScheme.primary`）ではなく、各UIスタイルで固定された中立色（`colorScheme.onSurface`等）を使うこと。アクセントカラーはボタンの地色・ガラスUIのリムライトなど、背景の塗りとしてのみ使う（2026-09-01の教訓、確認ダイアログの「今は同期しない」等の文字がアクセントカラーになり視認性を欠いた）。`lib/theme/app_theme.dart`・`lib/theme/glass/glass_theme.dart`・`lib/theme/gekiga/gekiga_theme.dart`の`textButtonTheme`で一括対応済みのため、個別のボタンで`foregroundColor`を指定する必要は無い。

  

> UI実装・レビュー時は`/home/arata/Obsidian-Personal/コマンド/UI参考.md`（DaiDai専用ではない一般的なUIデザイン原則・Tips集、git管理外）も参照すること。配色を絞る・ボタンの3階層化・確認ダイアログの構成・カードの角丸の決め方など、画面を作る/直すたびに当てはまる点が無いか確認する。

  

### UIスタイル（2026-07-22更新: フラット1本化＋カラーコード自由入力、2026-08-12改名: シンプル→フラット、2026-08-29追記: ガラス追加）

  

設定＞UIから、アプリ全体の見た目を`AppUiStyle`（`lib/models/app_ui_style.dart`）で切り替え可能（`lib/providers/app_ui_style_provider.dart`、端末のSharedPreferences永続化＋Firestore同期）。現在3種類:

  

- **フラット**（既定）: 以前はDaiDai（標準）/シンプルの2スタイル切り替えだったが、フラットスタイル1本に統合し、アクセントカラーを設定タブでカラーコード（`#RRGGBB`）から自由に指定できるようにした（`lib/theme/app_theme.dart`, `lib/providers/accent_color_provider.dart`, `lib/utils/color_hex.dart`, `lib/features/settings/settings_tab.dart`）。

- **劇画**（2026-07-29追加）: 手描き風・ギザギザした太い黒線・モノクロの吹き出しのスタイル（`lib/theme/gekiga/`, `lib/widgets/gekiga/`）。当初はメッセージ画面のみ対応の想定だったが、実際にはホーム・設定・身だしなみ等ほぼ全画面に`isGekiga`分岐という形で拡張済み。アクセントカラーの代わりに専用の背景色（`gekigaBackgroundColorProvider`）を使い、端末のライト/ダーク設定は無視して常に同じ見た目になる。

- **ガラス**（2026-08-29追加）: Apple Liquid Glassのような、すりガラス越しに背景が透けるスタイル。アクセントカラーは背景を塗らず、マテリアルの縁のうっすらとした光彩（リムライト）としてのみ表れる。`lib/theme/glass/`（`GlassTheme.build`、`GlassThemeExtras`）と`lib/widgets/glass/`（`GlassSurface`が中核の再利用ウィジェット、`GlassAppBar`/`GlassAlertDialog`/`showGlassModalBottomSheet`）で構成。`GlassVariant`で用途別に`BackdropFilter`を使うか（`chrome`=常設の全面パネル1点物、AppBar・ナビチップ・語らい画面の入力欄コンテナ/寄合タブバー/寄合一覧サイドバー、`floating`=ダイアログ・ボトムシート）使わないか（`card`=チャット吹き出し・設定項目等、画面に多数並ぶ面は性能上ぼかさない）を切り替える。劇画と異なり端末のライト/ダーク設定を尊重する。ほぼ全画面（ホーム・設定・身だしなみ・語らい・各種ダイアログ）に適用済み。

- **マテリアルに影（`boxShadow`等）を一切使わない**（2026-08-29決定）。`GlassSurface`（`lib/widgets/glass/glass_surface.dart`）に影を描く仕組み自体が無く、面の境界は縁ストローク（`enableEdgeStroke`、`BorderRadius.zero`の全面パネルでは直線が不要な線に見えるため無効化）と`BackdropFilter`によるぼかし（`chrome`/`floating`バリアント）のみで表現する。同色の背景に全面パネルが溶け込んで見えないようにするには、`card`（ぼかし無し）ではなく`chrome`/`floating`を選ぶこと。**唯一の例外**（2026-08-30追加）: ハンバーガーメニューのアイコンのみ、ユーザー指示により影を残す（`GlassIconBadge`の`shadow`パラメータ、`GlassSurface`自体には手を入れずバッジの外側にのみ`DecoratedBox`で乗せている）。他の要素へ同様の影を追加依頼された場合も、無断で全体方針を崩さずこのバッジ単位のオプトインパターンを踏襲すること。
- ガラスUIの文字・アイコン色は`GlassTheme`が生成する`ColorScheme`の`onSurface`/`onSurfaceVariant`を`GlassColors.lightForeground`/`darkForeground`（アクセントカラー非依存の固定色）に上書き済み。`ColorScheme.fromSeed`任せにすると選んだアクセントカラーの色相が文字色に乗り視認性が落ちるため、個別ファイルではなくテーマ側で一括固定する方針。

  

- ベース: mobbin.com「one year」（iOSアプリ）を参考にしたミニマルスタイル。等幅フォント、装飾を減らした余白多めのレイアウト。参考アプリ独自の手書きドット/イラストアイコン素材は模倣していない（配色・フォント・レイアウトの方向性のみ参考にした）

- 配色: アクセントカラー（既定値 `#3D2EE0`）を`ColorScheme.fromSeed`のseedにして全体のカラースキームを導出。ユーザーが設定タブでカラーコードを入力すると即座に全画面へ反映される

- ホーム画面のタブ切り替えもメニューバー（下部ナビ/サイドレール）をやめ、独立した丸いチップ（`_NavChip`, `lib/features/home/home_screen.dart`）を浮かせる形にした。選択中のチップはアクセントカラーで塗る

  

### ダークモード（2026-07-27実装、無料版で提供）

  

以前は「極みプランへの誘導優先」の方針で意図的に未実装だったが、ユーザー判断で方針を変更し無料版でも実装した（上記「実装しない機能」表から削除済み）。設定＞アプリケーションの「外観」からライト／ダーク／端末に合わせる、の3つを切り替え可能（`lib/providers/theme_mode_provider.dart`、端末のSharedPreferencesに永続化）。ダーク時の背景・カード色はアクセントカラーの色相に引っ張られない中立の**ダークグレー**（背景`#121212`・カード`#1E1E1E`）に固定しており、アクセントカラー自体はボタン等に引き続き反映される（`lib/theme/app_theme.dart`の`AppTheme.light`/`AppTheme.dark`）。

  

## 競合調査・差別化提案（2026-07-24追加）

  

競合・市場調査の結果はリポジトリ直下の`競合調査.md`（git管理下）に蓄積する。新しい調査ほど先頭に追記する運用（`日記.md`と同じ）。調査自体は`.claude/agents/market-research.md`で定義したサブエージェント（`market-research`）に委任できる。

  

- 機能追加・仕様決定・ポジショニングなど、プロダクトの方向性に関わる指示を受けたときは、着手前に`競合調査.md`に関連する調査が既にないか確認し、あれば踏まえた上で「競合と比べてこう差別化できる」という提案を一言添えること。単純なバグ修正・UIの微調整など競合比較が意味を持たない指示では不要

- `競合調査.md`に該当する調査がまだない場合、無理に推測で差別化提案をせず、必要なら`market-research`サブエージェントでの調査を提案する

- 競合調査の結果を根拠に、CLAUDE.mdの既存方針（「実装しない機能」表など）を覆すような提案をする場合は、決定事項として書かず、あくまで検討材料としてユーザーに判断を仰ぐ

  

## Sumomoとの関係

  

Sumomo（別プロダクト、公的機関向け）とDaiDaiは完全に別サーバーで運用。SumomoからDaiDai/Rhingの情報を参照することは不可（実装上もデータ・インフラを混在させない）。

  

作業前に日記.mdを必ず確認すること

作業後は必ずホットリロードすること。ただし`http://localhost:8765/`はFloorpにブックマーク済みで、動作確認はユーザー自身がそちらで行うため、確認のためにこちら側でブラウザ（Vivaldi等）を起動してアクセスする必要は無い