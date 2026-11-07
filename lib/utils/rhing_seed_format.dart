/// Rhing Seedの形式（英数字・`.`・`-`・`_`のみ、1〜20文字、大文字小文字は区別しない）。
/// 初回登録（`rhing_seed_setup_screen.dart`）と変更（`rhing_seed_change_dialog.dart`）で
/// 共用する。サーバー側（`functions/src/rhingSeedChange.ts`）と揃えること。
final RegExp rhingSeedPattern = RegExp(r'^[a-zA-Z0-9._-]{1,20}$');

/// Rhing Seedを変更できる間隔（日）。`functions/src/rhingSeedChange.ts`の
/// `SEED_CHANGE_INTERVAL_DAYS`と揃えること。
const int kRhingSeedChangeIntervalDays = 100;

/// 変更前のSeedを予約し、旧招待リンクを新Seedへ転送する期間（日）。
const int kRhingSeedAliasDays = 60;
