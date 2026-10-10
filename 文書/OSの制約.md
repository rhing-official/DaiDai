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
