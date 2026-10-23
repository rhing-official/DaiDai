# OSの制約

DaiDaiの実装では回避できない、OS・通信規格レベルの技術的制約をまとめる。「競合調査.md」と同じ運用で、新しい調査ほど上に追記する。

各エントリは次の形式:

```markdown
## YYYY-MM-DD テーマ

### 結論
### 原因
### DaiDai側コードの確認結果
### 対応方針
```

---

## 2026-10-23 iPad（WebKit）のブラウザで、通話中に向きを変えると映像が送れない／上下反転する

### 結論
**iPad（iPadOS）のブラウザ固有の可能性が高い**。DaiDaiの実装では直せておらず、**一旦放置する**（2026-10-23、ユーザー判断）。スマホ（ブラウザ）では、同じコード・同じ画面の向き変更で再現しない。ただし、原因は断定できていない（下記「未確定の点」）。

### 症状
- iPad（Firefox）で通話中に縦向きにすると、相手へ映像が送られない。横向きに戻すと送られる。
- 横向きでも、ホームボタンが左なら正しい向きで届くが、右にすると上下が反転して相手に表示される。

### 原因（推定）
- iPadのFirefoxは、iOS/iPadOSの制約でブラウザ独自のエンジンを使えず、**Safariと同じWebKit**上で動く。そのため、iPadのFirefoxとSafariは、カメラ・WebRTCの挙動が同じになる。
- WebKit側に、iPadの向き変更や逆向き（reverse portrait）で、カメラ映像の向きが崩れる既知の不具合報告がある（WebKit Bugzilla 213993・203403・201137・299591など。iPadOS 26でホーム画面アプリの向きが回る不具合の報告もある）。
- iOSは、向きの変化を映像フレームの回転情報（RTPの`video-orientation`拡張）で伝える。受信側のブラウザが解釈しないと、上下反転や向き違いになる。
- **未確定の点**: 手元にiPadが無く、送信側の統計やトラックの状態を確認していない。縦向きで送信が止まる原因が、(a) WebKitがカメラのキャプチャを止める、(b) 受信側が縦向きの解像度変更に追従しない、のどちらかは特定できていない。

### DaiDai側コードの確認結果
- 2026-10-22に、次の対症を入れた（Webのみで動く）。**iPadの症状は改善しなかった**。
  - 画面が縦向きの時は、カメラ解像度の縦横を入れ替える（`lib/features/call/webrtc_media_constraints.dart`の`buildVideoConstraints`）。
  - 向きが変わって約0.6秒落ち着いたら、カメラを取り直して送信中の映像を差し替える（`lib/features/call/camera_orientation_restart.dart`、`lib/utils/screen_orientation/`、1対1・広場の両方のコントローラー）。
- スマホでは副作用の報告が無いため、コードは残す。
- 1対1の発信側の映像枠をストリームに紐づける修正（2026-10-22）は、別件でこの症状とは無関係。

### 対応方針
- **一旦放置する**。送信前に映像を回転させる等の、追加の回避策は作らない。
- 再開する時の手がかり:
  1. iPad実機とMacのリモートインスペクタで、縦向きにした前後の送信側の統計（`getStats`の`framesSent`・`frameWidth`・`frameHeight`）と、`MediaStreamTrack`の`muted`・`readyState`を確認する。
  2. 縦向きで止まるなら、取り直しの方法を変える（旧トラックを止める前に新トラックを取得する、`applyConstraints`を使う、`aspectRatio`を指定する）。
  3. 上下反転が送信側のフレーム回転情報によるものなら、`canvas.captureStream`で送信前に向きを焼き込む（CPU負荷とバッテリーの消費が大きい）。
  4. iPadのSafari単体・Chromeでも同じか、受信側を別の端末（PC・Android）にして比べる。

---

## 2026-09-12 無線オーディオ（Bluetooth）通話中に音楽の音質が低下・途切れる

### 結論
原因はOS/Bluetooth規格レベルの制約であり、DaiDaiのアプリ側コードに起因する不具合ではない。他のSNS/通話アプリでも同様に発生する既知の制約で、アプリ単体では解決できない。

### 原因
- 通話でマイクを使用する（`getUserMedia`）と、Android/iOSはOS標準の「音声通話用」オーディオセッションを有効化する（Android: `AudioManager.MODE_IN_COMMUNICATION`＋`AUDIOFOCUS_GAIN`、iOS: `AVAudioSessionCategoryPlayAndRecord`）。
- これに伴い、OSはBluetoothデバイスを高音質・ステレオのA2DPプロファイルから、通話用の低ビットレート・モノラルのHFP/SCOプロファイルへ強制的に切り替える。
- 同時に再生されている音楽もこのHFPコーデックに引きずられ、音質低下・途切れとして体感される。これはBluetooth規格・OSのオーディオセッション管理の仕様そのものであり、特定アプリの実装不備ではない。

### DaiDai側コードの確認結果
- `lib/features/call/webrtc_media_constraints.dart`: エコーキャンセレーション等の制約はあるが、Bluetoothプロファイル制御とは無関係。
- `lib/features/call/webrtc_call_controller.dart:513-538`・`webrtc_group_call_controller.dart:552-576`: `Helper.setSpeakerphoneOn`によるスピーカー/イヤピース切替のみ実装。Bluetoothデバイスの選択・優先度・プロファイルを制御するコードは無い。
- Android/iOSともに、`flutter_webrtc`パッケージ側のデフォルト設定（Android: `AudioSwitchManager`の`MODE_IN_COMMUNICATION`、iOS: `AudioUtils.m`の`PlayAndRecord`+`AllowBluetoothA2DP`）がそのまま使われている。これはまさにHFP切替を誘発する標準構成であり、DaiDaiはこれを打ち消す設定を一切行っていない。
- iOS側には`flutter_webrtc`が持つ`appleAudioCategoryOptions`（`mixWithOthers`/`duckOthers`等を指定できるフック）があるが、DaiDaiのDartコードから利用されている箇所は無い（未使用）。ただしこれを使っても「通話中に他アプリの音声を鳴らし続けるかどうか」が変わるだけで、HFP切替自体（音質低下の根本原因）は防げない。
- `ios/Runner/Info.plist`・`android/app/src/main/AndroidManifest.xml`にも、オーディオセッションカテゴリやBluetoothプロファイルの挙動を左右する追加設定は無い。
- 着信音・呼出音（`calling_sound_provider.dart`/`ringtone_sound_provider.dart`/`call_sound_player.dart`）は音源選択・再生のみで、オーディオセッション設定には非関与。

### 対応方針
コード変更は行わない。OS/Bluetooth規格レベルの制約であり、アプリ側での解決策は存在しないと判断（ユーザー確認済み、2026-09-12）。
