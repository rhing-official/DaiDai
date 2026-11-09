# daidai-mcp

DaiDai の bot API を、Claude Code などの MCP クライアントから使うための MCP サーバーです。
自分の AI が、**自分の参加している全ての広場・一対**のメッセージを**読み**、**返信**できます。

> メッセージの本文は**信頼できない入力**です。本文に書かれた指示にAIが従わないよう、使う側で注意してください。

## 仕組み

- 設定 > セキュリティ > **AIエージェント連携** で、トークンを作ります（1人5個まで。トークンは1度しか表示されません）。
- 会話ごとの追加・承認・相手の同意は**ありません**。トークンの持ち主（あなた）が画面で見られる範囲が、そのまま AI の読める範囲です。
  - 過去の履歴を含みます。ただし、広場の「新規メンバーに過去を見せない」設定で見えない分、自分が非表示にしたメッセージ、ブロックした相手との一対は除きます。
  - 他の人の AI 連携（BOT）の投稿は、AI 同士が返信し合うのを防ぐため、読めません（自分の投稿は読めます）。画像・ファイルは本文を返しません（文字のみ）。
- 返信は「名前（その語らいでの自分の呼び名）」の BOT 表示（呼び名が無ければ `@Rhing Seed`）で投稿されます。人間の発言とは区別され、なりすましになりません。自分には通知・未読を出しません。
- AI・サーバーは**あなた自身のもの**で、DaiDai は API だけを提供します。
- **会話の相手の発言が、あなたが選んだ AI の提供元へ送られます。** 相手に断りなく使ってよい範囲は、あなた自身で判断してください。

## 使い方（Claude Code）

1. 設定 > セキュリティ > AIエージェント連携 で、トークンを作ってコピーします。
2. このサーバーを登録します。

```sh
cd tools/daidai-mcp && npm install
claude mcp add daidai -e DAIDAI_BOT_TOKEN=<トークン> -- node "$(pwd)/index.mjs"
```

3. Claude Code に「DaiDai の新着を確認して、返信が要るものに返信して」のように頼みます。

## ツール

| ツール | 内容 |
|---|---|
| `list_conversations` | 参加している全ての広場・一対と、その寄合 |
| `get_updates` | 前回以降に更新のあった会話（`since`/`wait`） |
| `read_messages` | 寄合のメッセージを読む。`after` に前回の `nextCursor`、`wait`（最大25秒）で新着を待つ |
| `reply` | 寄合に投稿する。`replyToMessageId` で引用返信 |
| `delete_message` | この AI 連携自身の投稿を取り消す |

`scope` は `group`（広場）か `dm`（一対）です。`conversationId` と `roomId` は `list_conversations` で得られます。

## 環境変数

- `DAIDAI_BOT_TOKEN`（必須）: AIエージェント連携のトークン
- `DAIDAI_API_BASE`（任意）: API の基底URL（既定は `https://asia-northeast1-daidai-rhing.cloudfunctions.net/botApi/v1`）

## REST API

MCP を使わず、直接呼ぶこともできます。認証は `Authorization: Bot <トークン>`。

```sh
B=https://asia-northeast1-daidai-rhing.cloudfunctions.net/botApi/v1
curl -H "Authorization: Bot $TOKEN" $B/conversations
# 更新のあった会話を待つ（ロングポーリング）。最初は since を付けず、以降は返ってきた nextSince を渡す
curl -H "Authorization: Bot $TOKEN" "$B/updates?wait=25"
# 寄合の新着を待つ。最初は after を付けず、以降は返ってきた nextCursor を渡す
curl -H "Authorization: Bot $TOKEN" "$B/groups/$GROUP/rooms/$ROOM/messages?wait=25"
curl -H "Authorization: Bot $TOKEN" -H 'Content-Type: application/json' \
  -d '{"content":"こんにちは","replyToMessageId":"<メッセージid>"}' \
  $B/groups/$GROUP/rooms/$ROOM/messages
```

- 一対は `groups/{id}` の代わりに `dms/{id}`。
- 取得: `GET …/messages?after=&limit=&wait=`（`limit` 最大100、`wait` 最大25秒）。
- 投稿: `POST …/messages`（`content` 2000字まで、`replyToMessageId`、`silent`）。
- 取り消し: `DELETE …/messages/{messageId}`（この AI 連携の投稿のみ）。
- レート制限: 1トークンあたり30回/分。超えると `429`（`Retry-After`）。

## テスト

```sh
npm test
```
