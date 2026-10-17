import 'guide_content.dart';

/// 操作を促すインタラクティブなガイド（2026-10-17追加）の台本。日本語を含む文言は
/// `lib/features/`に直書きできないため、この`lib/l10n/`に置く。日本語・英語のみで、
/// それ以外の表示言語は英語にフォールバックする（フランス語等は後から追加）。

/// 画面上の「押す場所」の目印のid（`TutorialTarget`に渡す）。
abstract final class TutorialTargetIds {
  /// ホームのナビチップ「身だしなみ」。
  static const navProfile = 'nav-profile';

  /// 身だしなみの「縁結び」の行。
  static const profileEnmusubi = 'profile-enmusubi';

  /// 縁結び画面の「招待リンクをコピー」ボタン。
  static const enmusubiCopy = 'enmusubi-copy';

  /// 縁結び画面の自分のQRコード。
  static const enmusubiQr = 'enmusubi-qr';

  /// 縁結び画面の「QRコードを読み取る」ボタン。
  static const enmusubiScan = 'enmusubi-scan';
}

/// 台本の1手順。[requiresTap]が`true`なら[targetId]の目印が押されると次へ進む。
/// `false`（情報の手順）なら、目印を丸で示して説明するだけで、画面全体のタップを
/// 止め、吹き出しの「次へ」で進める（カメラの許可が絡むボタンなど、押させたくない
/// 場所の説明に使う）。
class TutorialStep {
  const TutorialStep({
    required this.targetId,
    required this.caption,
    this.requiresTap = true,
  });

  final String targetId;
  final GuideText caption;
  final bool requiresTap;
}

/// 1本の台本。最後の手順を終えると[doneMessage]を出して終わる。
class TutorialScript {
  const TutorialScript({
    required this.id,
    required this.steps,
    required this.doneMessage,
    required this.stageRoute,
  });

  /// `GuideTopic.id`と同じ値にすると、そのトピックの詳細から開始できる。
  final String id;
  final List<TutorialStep> steps;
  final GuideText doneMessage;

  /// ガイドを実行する専用ルート。ユーザーの今の画面の上に全画面で開き、終了すると
  /// 閉じて元の画面に戻る（作業中の状態に左右されず、邪魔もしない）。
  final String stageRoute;
}

/// 縁結び（友達を追加する）。練習用のホーム（本物の画面に偽のデータを入れた
/// 仮環境）を専用ルートで開き、ホームの「身だしなみ」→「縁結び」の道順から、
/// 縁結び画面の操作までを実際に押して覚える。
const friendsTutorial = TutorialScript(
  id: 'friends',
  stageRoute: '/guide/enmusubi',
  steps: [
    TutorialStep(
      targetId: TutorialTargetIds.navProfile,
      caption: GuideText('まず「身だしなみ」を押します', 'First, tap "Profile"'),
    ),
    TutorialStep(
      targetId: TutorialTargetIds.profileEnmusubi,
      caption: GuideText(
        '次に「縁結び」を押します。友達を追加する画面です',
        'Next, tap "Add Friend" to open the screen for adding friends',
      ),
    ),
    TutorialStep(
      targetId: TutorialTargetIds.enmusubiCopy,
      caption: GuideText(
        'ここを押すと、あなたの招待リンクがコピーされます',
        'Tap here to copy your invite link',
      ),
    ),
    TutorialStep(
      targetId: TutorialTargetIds.enmusubiQr,
      requiresTap: false,
      caption: GuideText(
        'これがあなたのQRコードです。相手に見せて、読み取ってもらうこともできます',
        'This is your QR code. You can also show it to someone and let them scan it',
      ),
    ),
    TutorialStep(
      targetId: TutorialTargetIds.enmusubiScan,
      requiresTap: false,
      caption: GuideText(
        '相手のQRコードを読み取るときは、このボタンを押します',
        'To scan someone else\'s QR code, tap this button',
      ),
    ),
  ],
  doneMessage: GuideText(
    'これで友達を追加する準備ができました。実際は、あなた専用の招待リンクを友達にメッセージなどで送ると、友達になれます。',
    'You are ready to add friends. In the real app, send your own invite link to a friend in a message to connect.',
  ),
);

/// 台本がまだ無い機能ガイドを押したときの案内。
const guideComingSoon = GuideText('このガイドは準備中です', 'This guide is coming soon');

const tutorialScripts = <TutorialScript>[friendsTutorial];

/// [id]の台本。無ければ`null`。
TutorialScript? tutorialScriptOf(String id) {
  for (final script in tutorialScripts) {
    if (script.id == id) return script;
  }
  return null;
}
