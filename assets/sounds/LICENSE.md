# 同梱音源ライセンス（着信音・呼出音・通知音プリセット）

`lib/models/sound_preset.dart`のプリセットで使用している本番音源の出典・ライセンス一覧（2026-09-12差し替え）。

## 着信音・呼出音 共通プリセット

| ファイル | プリセットid | 出典 | ライセンス |
|---|---|---|---|
| `phonebooth_ring.mp3` | `phonebooth_ring` | [BigSoundBank: Telephone booth ringtone #1](https://bigsoundbank.com/telephone-booth-ringtone-1-s3364.html)（Joseph SARDIN氏、フランス・ムルバッハの公衆電話ボックスの実録音） | CC0（パブリックドメイン相当）、帰属表示不要 |
| `marimba_ring.mp3` | `marimba_ring` | [Mixkit: Marimba ringtone](https://mixkit.co/free-sound-effects/phone/) | Mixkit Free License、帰属表示不要 |
| `european_ringback.mp3` | `european_ringback` | [BigSoundBank: Tone, Ringback Tone #1](https://bigsoundbank.com/tone-ringback-tone-1-s1614.html)（Joseph SARDIN氏、425Hz正弦波、欧州の固定電話規格） | CC0（パブリックドメイン相当）、帰属表示不要 |
| `futuristic_dial.mp3` | `futuristic_dial` | [Mixkit: Futuristic dial tone](https://mixkit.co/free-sound-effects/phone/) | Mixkit Free License、帰属表示不要 |

## 通知音プリセット（Android限定）

| ファイル | プリセットid | 出典 | ライセンス |
|---|---|---|---|
| `notification_lasomarie.mp3` | `notification_lasomarie` | [BigSoundBank: Notification, "LaSoMarie" #1](https://bigsoundbank.com/notification-lasomarie-1-s2059.html)（Joseph SARDIN氏、Cubase「Prologue」音源で制作） | CC0（パブリックドメイン相当）、帰属表示不要 |
| `notification_message_pop.mp3` | `notification_message_pop` | [Mixkit: Message pop alert](https://mixkit.co/free-sound-effects/notification/) | Mixkit Free License、帰属表示不要 |
| `notification_happy_bells.mp3` | `notification_happy_bells` | [Mixkit: Happy bells notification](https://mixkit.co/free-sound-effects/notification/) | Mixkit Free License、帰属表示不要 |

同じファイルを`android/app/src/main/res/raw/`にも配置している（Android通知チャンネルのraw resourceとして参照するため、`push_notifications.dart`の`_notificationChannels`参照）。

## 除外方針

Apple社のiPhone標準着信音・通知音と同名・同一の説明が付く音源（BigSoundBankの「Ouverture」「Marimba」「iPhone - Ringtone "Alarm"/"Sonar"」等、LINE/Discord等の実在SNSアプリの音源そのもの）は、著作権・商標上のリスクを避けるため候補から除外している。
