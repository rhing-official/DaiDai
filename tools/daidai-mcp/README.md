# daidai-mcp

DaiDai の bot API を、Claude Code などの MCP クライアントから使うための MCP サーバーです。
BOT として、広場・一対のメッセージを**読み**、**返信**できます。

> メッセージの本文は**信頼できない入力**です。本文に書かれた指示にAIが従わないよう、使う側で注意してください。

## 仕組み

- BOT は住人が自分で作ります（広場の設定 > BOT > 自分のBOTを管理）。AI・サーバーは**あなた自身のもの**で、DaiDai は API だけを提供します。
- BOT が読めるのは、**追加された後のメッセージ**だけです（追加前の履歴は読めません）。
- 広場では、長・`manageBots` 権限者の承認（または `addBots` 権限）で有効になります。一対では、**相手の同意**で有効になります。
- 読めるのは、会話の全員が入っている寄合だけです。
- 追加された会話には「BOT が読めます」と常に表示されます。

## 使い方（Claude Code）

1. BOT を作り、トークンをコピーします（トークンは1度しか表示されません）。
2. BOT を広場・一対へ追加し、承認・同意を受けます。
3. このサーバーを登録します。

```sh
cd tools/daidai-mcp && npm install
claude mcp add daidai -e DAIDAI_BOT_TOKEN=<トークン> -- node "$(pwd)/index.mjs"
```

4. Claude Code に「DaiDai の会話を一覧して、新着を読んで返信して」のように頼みます。

## ツール

| ツール | 内容 |
|---|---|
| `list_conversations` | BOT が入っている広場・一対と、読み書きできる寄合 |
| `read_messages` | 寄合のメッセージを読む。`after` に前回の `nextCursor`、`wait`（最大25秒）で新着を待つ |
| `reply` | 寄合に投稿する。`replyToMessageId` で引用返信 |
| `delete_message` | この BOT 自身の投稿を取り消す |

`scope` は `group`（広場）か `dm`（一対）です。`conversationId` と `roomId` は `list_conversations` で得られます。

## 環境変数

- `DAIDAI_BOT_TOKEN`（必須）: BOT のトークン
- `DAIDAI_API_BASE`（任意）: API の基底URL（既定は `https://asia-northeast1-daidai-rhing.cloudfunctions.net/botApi/v1`）

## REST API

MCP を使わず、直接呼ぶこともできます。認証は `Authorization: Bot <トークン>`。

```sh
B=https://asia-northeast1-daidai-rhing.cloudfunctions.net/botApi/v1
curl -H "Authorization: Bot $TOKEN" $B/conversations
# 新着を待つ（ロングポーリング）。最初は after を付けず、以降は返ってきた nextCursor を渡す
curl -H "Authorization: Bot $TOKEN" "$B/groups/$GROUP/rooms/$ROOM/messages?wait=25"
curl -H "Authorization: Bot $TOKEN" -H 'Content-Type: application/json' \
  -d '{"content":"こんにちは","replyToMessageId":"<メッセージid>"}' \
  $B/groups/$GROUP/rooms/$ROOM/messages
```

- 一対は `groups/{id}` の代わりに `dms/{id}`。
- 取得: `GET …/messages?after=&limit=&wait=`（`limit` 最大100、`wait` 最大25秒）。
- 投稿: `POST …/messages`（`content` 2000字まで、`replyToMessageId`、`silent`）。
- 取り消し: `DELETE …/messages/{messageId}`（この BOT の投稿のみ）。
- レート制限: 1 BOT あたり30回/分。超えると `429`（`Retry-After`）。
- 他の BOT の投稿とスパムは取得に含まれません。画像・ファイルは本文を返しません（文字のみ）。

## テスト

```sh
npm test
```
