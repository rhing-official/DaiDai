import 'guide_content.dart';

/// 操作を促すインタラクティブなガイド（2026-10-17追加）の台本。日本語を含む文言は
/// `lib/features/`に直書きできないため、この`lib/l10n/`に置く。日本語・英語のみで、
/// それ以外の表示言語は英語にフォールバックする（フランス語等は後から追加）。

/// 画面上の「押す場所」の目印のid（`TutorialTarget`に渡す）。
abstract final class TutorialTargetIds {
  /// ホームのナビチップ「身だしなみ」。
  static const navProfile = 'nav-profile';

  /// ホームのナビチップ「語らい」。
  static const navTalk = 'nav-talk';

  /// 身だしなみの「蔵」の行。
  static const profileKura = 'profile-kura';

  /// 身だしなみの「仕立て」の行。
  static const profileKoubou = 'profile-koubou';

  /// 身だしなみの「縁結び」の行。
  static const profileEnmusubi = 'profile-enmusubi';

  /// 練習用の語らい一覧の、練習相手の行。
  static const practiceFriend = 'practice-friend';

  /// 語らい一覧の「一対」タブ・「広場」タブ・＋（追加）ボタン。
  static const talkCategoryDm = 'talk-category-dm';
  static const talkCategoryGroup = 'talk-category-group';
  static const talkAdd = 'talk-add';

  /// 会話の上部の電話・ビデオ通話・アルバム・ノート・カレンダーのボタン。
  static const chatCallButton = 'chat-call';
  static const chatVideoButton = 'chat-video';
  static const chatAlbumButton = 'chat-album';
  static const chatNoteButton = 'chat-note';
  static const chatCalendarButton = 'chat-calendar';

  /// 会話のメッセージ入力欄。
  static const chatInput = 'chat-input';

  /// 会話の送信ボタン（文字が入っている間だけ現れる）。
  static const chatSend = 'chat-send';

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
///
/// [advanceWhenVisible]を指定すると、その目印が画面に現れた時点で次へ進む
/// （入力欄に文字が入ると送信ボタンが現れる、のように、押す以外で進む手順）。
class TutorialStep {
  const TutorialStep({
    required this.targetId,
    required this.caption,
    this.requiresTap = true,
    this.advanceWhenVisible,
    this.showCircle = true,
    this.fallbackTargetId,
  });

  final String targetId;
  final GuideText caption;
  final bool requiresTap;
  final String? advanceWhenVisible;

  /// 手描きの丸を描くか。入力欄のように横に長い目印は、丸が被って見づらいため、
  /// 明るく抜くだけにして丸は描かない。
  final bool showCircle;

  /// [targetId]の目印がまだ現れていない間に、代わりに明るく抜いて操作できるようにする
  /// 目印（丸は描かない）。
  final String? fallbackTargetId;
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

/// 練習用の画面（[stageRoute]）。本物の画面に偽のデータを入れた仮環境。
const practiceStageRoute = '/guide/practice';

/// 身だしなみ（蔵・仕立て）。「身だしなみ」を押して、蔵と仕立てを丸で示して説明する。
const _profileChipStep = TutorialStep(
  targetId: TutorialTargetIds.navProfile,
  caption: GuideText('まず「身だしなみ」を押します', 'First, tap "Profile"'),
);

const _profileSteps = <TutorialStep>[
  _profileChipStep,
  TutorialStep(
    targetId: TutorialTargetIds.profileKura,
    requiresTap: false,
    caption: GuideText(
      '「蔵」は、アイコンや背景画像、呼び名などの素材をしまっておく場所です',
      'The "Material Box" is where you keep your icons, background images, nicknames and other materials',
    ),
  ),
  TutorialStep(
    targetId: TutorialTargetIds.profileKoubou,
    requiresTap: false,
    caption: GuideText(
      '「仕立て」では、蔵の素材を組み合わせて、プロフィールカードを仕立てます',
      'In "Tailoring", combine your materials to make profile cards',
    ),
  ),
];

/// 縁結び（友達を追加する）。身だしなみの中の「縁結び」を押すところから。
const _friendsSteps = <TutorialStep>[
  TutorialStep(
    targetId: TutorialTargetIds.profileEnmusubi,
    caption: GuideText(
      '「縁結び」を押します。友達を追加する画面です',
      'Tap "Add Friend" to open the screen for adding friends',
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
];

/// メッセージの送り方。「語らい」から相手を選び、入力して送信する。
const _messageSteps = <TutorialStep>[
  ..._openChatSteps,
  TutorialStep(
    targetId: TutorialTargetIds.chatInput,
    advanceWhenVisible: TutorialTargetIds.chatSend,
    showCircle: false,
    caption: GuideText(
      'ここにメッセージを入力します。何か書いてみてください',
      'Type your message here. Try writing something',
    ),
  ),
  TutorialStep(
    targetId: TutorialTargetIds.chatSend,
    fallbackTargetId: TutorialTargetIds.chatInput,
    caption: GuideText(
      '送信ボタンを押すと、メッセージが送られます',
      'Tap the send button to send it',
    ),
  ),
];

/// 練習相手との会話を開くまでの手順（語らい→相手）。会話の画面で完結するガイドの前置き。
const _openChatSteps = <TutorialStep>[
  TutorialStep(
    targetId: TutorialTargetIds.navTalk,
    caption: GuideText(
      '「語らい」を押します。会話の一覧です',
      'Tap "Talks" to see your conversations',
    ),
  ),
  TutorialStep(
    targetId: TutorialTargetIds.practiceFriend,
    caption: GuideText(
      '話したい相手を押して、会話を開きます',
      'Tap the person you want to talk to',
    ),
  ),
];

/// 一対と広場。語らいの一覧の切り替えと追加ボタン。
const directPlazaTutorial = TutorialScript(
  id: 'direct-plaza',
  stageRoute: practiceStageRoute,
  steps: [
    TutorialStep(
      targetId: TutorialTargetIds.navTalk,
      caption: GuideText(
        '「語らい」を押します。会話の一覧です',
        'Tap "Talks" to see your conversations',
      ),
    ),
    TutorialStep(
      targetId: TutorialTargetIds.talkCategoryDm,
      requiresTap: false,
      caption: GuideText(
        '「一対」は、1人の相手と2人で話す場所です',
        '"Direct" is a place for talking one-to-one with a single person',
      ),
    ),
    TutorialStep(
      targetId: TutorialTargetIds.talkCategoryGroup,
      caption: GuideText(
        '「広場」を押してみましょう。3人以上で集まる場所です',
        'Tap "Plaza". It is a place for three or more people to gather',
      ),
    ),
    TutorialStep(
      targetId: TutorialTargetIds.talkAdd,
      requiresTap: false,
      caption: GuideText(
        'ここから、友達の追加や、新しい広場の作成ができます',
        'From here you can add a friend or create a new Plaza',
      ),
    ),
  ],
  doneMessage: GuideText(
    '一対は2人の会話、広場は大勢の集まりです。広場の中は、話題ごとに「寄合」で分けられます。',
    'A Direct is a two-person chat and a Plaza is a gathering. Inside a Plaza you can split topics into channels.',
  ),
);

/// 通話。会話の上部の電話ボタンを説明する（練習中は通話を始めない）。
const callsTutorial = TutorialScript(
  id: 'calls',
  stageRoute: practiceStageRoute,
  steps: [
    ..._openChatSteps,
    TutorialStep(
      targetId: TutorialTargetIds.chatCallButton,
      requiresTap: false,
      caption: GuideText(
        'ここを押すと音声通話が始まります。隣のカメラのボタンでビデオ通話もできます（練習中は始まりません）',
        'Tap here to start a voice call. The camera button next to it starts a video call (nothing starts during practice)',
      ),
    ),
  ],
  doneMessage: GuideText(
    '通話中は、画面を小さくして、他の画面を見ながら続けることもできます。',
    'During a call you can shrink the screen and keep going while you look at other things.',
  ),
);

/// アルバム。会話の上部のボタンから開く。
const albumTutorial = TutorialScript(
  id: 'album',
  stageRoute: practiceStageRoute,
  steps: [
    ..._openChatSteps,
    TutorialStep(
      targetId: TutorialTargetIds.chatAlbumButton,
      caption: GuideText(
        'このボタンで、会話のアルバムを開きます',
        'Tap this button to open the album of this conversation',
      ),
    ),
  ],
  doneMessage: GuideText(
    'メッセージの写真や動画をアルバムに追加すると、メッセージの保存期間が過ぎても残せます。',
    'Add photos and videos from messages to the album to keep them even after the message retention period.',
  ),
);

/// ノート。会話の上部のボタンから開く。
const notesTutorial = TutorialScript(
  id: 'notes',
  stageRoute: practiceStageRoute,
  steps: [
    ..._openChatSteps,
    TutorialStep(
      targetId: TutorialTargetIds.chatNoteButton,
      caption: GuideText(
        'このボタンで、会話のノートを開きます',
        'Tap this button to open the notes of this conversation',
      ),
    ),
  ],
  doneMessage: GuideText(
    'ノートには、文章・見出し・リスト・表などを書きためられます。',
    'In notes you can write text, headings, lists and tables.',
  ),
);

/// カレンダー。会話の上部のボタンから開く。
const calendarTutorial = TutorialScript(
  id: 'calendar',
  stageRoute: practiceStageRoute,
  steps: [
    ..._openChatSteps,
    TutorialStep(
      targetId: TutorialTargetIds.chatCalendarButton,
      caption: GuideText(
        'このボタンで、会話のカレンダーを開きます',
        'Tap this button to open the calendar of this conversation',
      ),
    ),
  ],
  doneMessage: GuideText(
    '予定を追加して共有できます。日程調整では、候補日を出してみんなの都合を集められます。',
    'You can add and share events. With scheduling, propose dates and gather everyone\'s availability.',
  ),
);

/// 縁結び（機能別ガイド）。身だしなみのチップから始める。
const friendsTutorial = TutorialScript(
  id: 'friends',
  stageRoute: practiceStageRoute,
  steps: [_profileChipStep, ..._friendsSteps],
  doneMessage: GuideText(
    'これで友達を追加する準備ができました。実際は、あなた専用の招待リンクを友達にメッセージなどで送ると、友達になれます。',
    'You are ready to add friends. In the real app, send your own invite link to a friend in a message to connect.',
  ),
);

/// メッセージの送り方（機能別ガイド）。
const messagesTutorial = TutorialScript(
  id: 'messages',
  stageRoute: practiceStageRoute,
  steps: _messageSteps,
  doneMessage: GuideText(
    'メッセージを送れました。写真やファイル、ぺったんも、入力欄の近くのボタンから送れます。',
    'Your message is sent. You can also send photos, files and stickers from the buttons near the input field.',
  ),
);

/// 身だしなみ（機能別ガイド）。
const profileTutorial = TutorialScript(
  id: 'profile',
  stageRoute: practiceStageRoute,
  steps: _profileSteps,
  doneMessage: GuideText(
    '身だしなみで、自分のプロフィールを整えられます。蔵に素材を登録して、仕立てでカードを作ってみましょう。',
    'Use Profile to set up how you appear. Add materials to the Material Box, then make a card in Tailoring.',
  ),
);

/// 初回の使い方ガイド（新規登録直後）。身だしなみ→縁結び→メッセージを一続きで。
/// 縁結びは身だしなみの中にあるため、身だしなみを先に案内する。
const firstRunTutorial = TutorialScript(
  id: 'first-run',
  stageRoute: practiceStageRoute,
  steps: [..._profileSteps, ..._friendsSteps, ..._messageSteps],
  doneMessage: GuideText(
    '基本はこれでおしまいです。ほかの使い方は、「設定」の「運営」にある「使い方ガイド」から、いつでも見られます。',
    'That covers the basics. You can find other guides anytime in Settings > Support > User guide.',
  ),
);

/// 練習用の語らいに出る、練習相手の最初の挨拶。
const practiceGreeting = GuideText(
  'はじめまして！ メッセージを送ってみてください',
  'Nice to meet you! Try sending me a message',
);

/// 台本がまだ無い機能ガイドを押したときの案内。
const guideComingSoon = GuideText('このガイドは準備中です', 'This guide is coming soon');

/// 設定の使い方ガイド一覧から開始できる台本（[GuideTopic.id]と同じidのもの）。
/// 初回用の[firstRunTutorial]は一覧には出ない。
const tutorialScripts = <TutorialScript>[
  friendsTutorial,
  directPlazaTutorial,
  messagesTutorial,
  notesTutorial,
  calendarTutorial,
  albumTutorial,
  callsTutorial,
  profileTutorial,
];

/// [id]の台本。無ければ`null`。
TutorialScript? tutorialScriptOf(String id) {
  for (final script in tutorialScripts) {
    if (script.id == id) return script;
  }
  return null;
}
