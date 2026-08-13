---
name: server
description: DaiDaiの動作確認用Flutter Web環境（flutter run -d web-server --web-port=8765）をバックグラウンドで起動する。ユーザーが「/server」「起動して」「もう一度開いて」等、明示的に起動を求めたときに使う。
---

# /server

呼び出されたら、方針確認などを挟まず即座に以下を行う（CLAUDE.mdの「開発時の動作確認」節で事前承認済みの操作）。

## 1. 既存プロセスの確認

```bash
pgrep -af "flutter.*web-server"
```

- 既に起動済みの`flutter run -d web-server`プロセスが見つかった場合は、新規に起動し直さない。その旨をユーザーに伝え、PID（後述の「2. 起動」内のホットリロード/リスタート方法参照）を案内して終了する。
- 見つからなければ2へ進む。

## 2. 起動

`flutter`/`dart`はPATHに無いため、`~/flutter/bin/flutter`をフルパスで呼ぶ。

```bash
~/flutter/bin/flutter run -d web-server --web-port=8765
```

- `run_in_background: true`で実行する（フォアグラウンドで待つと以降の操作ができなくなるため）。
- 起動確認のため出力ファイルを`until`ループ等でポーリングし、`lib/main.dart is being served at http://localhost:8765`のような行が出るまで待つ（この待機自体は短時間の`sleep`ループで問題ない。ビルドに数十秒〜数分かかることがある）。
- `Error`や`lost connection`等が出た場合はその内容をそのままユーザーに報告する。
- 起動が確認できたら、`http://localhost:8765/`で確認できる旨をユーザーに伝える（動作確認はユーザー自身がFloorpのブックマークから行うため、こちら側でブラウザを開く必要は無い）。

## 3. 起動後の扱い（このセッション中の以降のやり取りで参照する）

CLAUDE.mdの運用ルールの通り:

- この後のコード変更は、確認を挟まず都度ホットリロード（`r`相当）を反映させる。`main()`やRiverpodの`ProviderScope`初期化変更、新規パッケージ追加時はホットリスタート（`R`相当）を使う。
- このバックグラウンドプロセスにはターミナルからの`r`/`R`キー入力を送れないため、代わりにプロセスのPIDへシグナルを送る。

```bash
kill -SIGUSR1 <pid>   # ホットリロード
kill -SIGUSR2 <pid>   # ホットリスタート
```

- PIDは起動時のBashツール実行結果、または`pgrep -af "flutter.*web-server"`で確認できる。
- シグナルでも反映されない場合（新規パッケージ追加直後など）は、このプロセスを終了し1〜2を再実行して完全に起動し直す。
