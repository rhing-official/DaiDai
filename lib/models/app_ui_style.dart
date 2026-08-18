/// アプリ全体の見た目のスタイル。端末ごとの個人設定で、自分の画面の
/// 見た目だけを変える（相手の語らいの表示には一切影響しない）。
///
/// 2026-07-29追加。現時点ではメッセージ画面（`ChatScreen`）と通話画面
/// （`CallScreen`/`GroupCallScreen`、2026-08-19対応）がこの値を見て見た目を
/// 切り替える。他の画面（ホーム・設定・身だしなみ等）はスタイルによらず
/// 常に[flat]相当の見た目のまま（段階的に対応範囲を広げる方針）。
enum AppUiStyle {
  /// 現行の標準スタイル（2026-08-12改名: シンプル→フラット）。
  flat,

  /// 手描き風・ギザギザした太い黒線・モノクロの吹き出し・アイコンを
  /// 丸で囲むデザイン。
  gekiga;

  static AppUiStyle fromName(String? name) {
    return AppUiStyle.values.firstWhere(
      (style) => style.name == name,
      orElse: () => AppUiStyle.flat,
    );
  }
}
