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

  /// ノートの一覧の1件（練習用の見本のノート）と、ノートの編集欄全体。
  static const noteListItem = 'note-list-item';
  static const noteEditor = 'note-editor';

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
    this.advanceOnEvent,
    this.freeform = false,
    this.captionAtTop = false,
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

  /// この名前の出来事が起きたら次へ進む（[TutorialController.notify]）。押す以外の
  /// 操作（エディタに文字を打つ、メニューを開く等）で進む手順に使う。目印を押しても
  /// 進まない。
  final String? advanceOnEvent;

  /// 画面を暗くせず、どこも止めずに、説明のカードだけを出す。エディタへの入力や、
  /// 位置が決まらないメニューの操作など、ユーザーが自由に触る手順に使う。
  /// [targetId]は使わない。
  final bool freeform;

  /// [freeform]のカードを画面の上に出す（既定は下。下に開くメニューを隠さないため）。
  final bool captionAtTop;
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
      'The "Profile library" is where you keep your icons, background images, nicknames and other materials',
    ),
  ),
  TutorialStep(
    targetId: TutorialTargetIds.profileKoubou,
    requiresTap: false,
    caption: GuideText(
      '「仕立て」では、蔵の素材を組み合わせて、プロフィールカードを仕立てます',
      'In the "Profile editor", combine your materials to make profile cards',
    ),
  ),
];

/// 縁結び（友達を追加する）。身だしなみの中の「縁結び」を押すところから。
const _friendsSteps = <TutorialStep>[
  TutorialStep(
    targetId: TutorialTargetIds.profileEnmusubi,
    caption: GuideText(
      '「縁結び」を押します。友達を追加する画面です',
      'Tap "Add friends" to open the screen for adding friends',
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

/// ノート。会話の上部のボタンからノートを開き、実際に書きながら使い方を覚える。
/// 練習用のノートは空で、見出し・リスト・太字・「+」の挿入を自分で試す。
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
    TutorialStep(
      targetId: TutorialTargetIds.noteListItem,
      caption: GuideText(
        '一覧からノートを選びます。ここでは、練習用のノートを開きます',
        'Choose a note from the list. Let\'s open the practice note',
      ),
    ),
    TutorialStep(
      targetId: TutorialTargetIds.noteEditor,
      requiresTap: false,
      showCircle: false,
      caption: GuideText(
        'ノートは、会話のみんなで一緒に書ける共有のメモです。書いた内容は、すぐ全員に反映されます。空の練習用ノートで、実際に書いてみましょう',
        'A note is a shared memo that everyone in the conversation can write together, and changes show up for everyone right away. Let\'s try writing in this empty practice note',
      ),
    ),
    TutorialStep(
      targetId: TutorialTargetIds.noteEditor,
      freeform: true,
      advanceOnEvent: 'note-heading',
      caption: GuideText(
        '1行目に「# 」（#と半角スペース）を打ってみましょう。続けて文字を打つと、大きな見出しになります',
        'Type "# " (a # and a space) on the first line, then some text. It becomes a large heading',
      ),
    ),
    TutorialStep(
      targetId: TutorialTargetIds.noteEditor,
      freeform: true,
      advanceOnEvent: 'note-bulleted',
      caption: GuideText(
        'Enterで次の行へ進み、「- 」（ハイフンと半角スペース）を打ってみましょう。箇条書きになります',
        'Press Enter for a new line, then type "- " (a hyphen and a space). It becomes a bulleted list',
      ),
    ),
    TutorialStep(
      targetId: TutorialTargetIds.noteEditor,
      freeform: true,
      advanceOnEvent: 'note-numbered',
      caption: GuideText(
        '箇条書きを終えるには、空の項目でEnterを押します。そのあと「1. 」と打つと、番号つきのリストになります',
        'To end a bulleted list, press Enter on an empty item. Then type "1. " to start a numbered list',
      ),
    ),
    TutorialStep(
      targetId: TutorialTargetIds.noteEditor,
      freeform: true,
      advanceOnEvent: 'note-bold',
      caption: GuideText(
        '書いた文字を選ぶと、書式のメニューが出ます。太字にしてみましょう（「**太字**」のように記号で囲んで書いても同じです）',
        'Select some text you wrote to show the formatting menu, and make it bold. (Wrapping it like "**bold**" works too)',
      ),
    ),
    TutorialStep(
      targetId: TutorialTargetIds.noteEditor,
      freeform: true,
      advanceOnEvent: 'note-insert-menu',
      caption: GuideText(
        '「+」を押してみましょう。スマホでは画面上の「+」、パソコンではカーソルのある行の右に出る「+」です',
        'Tap "+". On phones it is at the top of the screen; on a computer it appears at the right of the line the cursor is on',
      ),
    ),
    TutorialStep(
      targetId: TutorialTargetIds.noteEditor,
      freeform: true,
      captionAtTop: true,
      advanceOnEvent: 'note-inserted',
      caption: GuideText(
        'ここから、見出し・リスト・引用・区切り線・表・目次・画像・音声・ファイル・リンクの埋め込みを入れられます。「区切り線」か「表」を選んでみましょう（パソコンでは、「/」を打っても同じメニューが開きます）',
        'From here you can add headings, lists, quotes, dividers, tables, a table of contents, images, audio, files and link embeds. Try a divider or a table. (On a computer, typing "/" opens the same menu)',
      ),
    ),
  ],
  doneMessage: GuideText(
    'これで、ノートの基本は以上です。書いた内容は、Markdownファイルとして書き出すこともできます。',
    'That covers the basics of notes. You can also export what you write as a Markdown file.',
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
    'Use Profile to set up how you appear. Add materials to the Profile library, then make a card in the Profile editor.',
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

/// 練習用のノートの題名（中身は空で、ガイドの中で書く）。
const practiceNoteTitle = GuideText('旅行の持ち物', 'Packing list');

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
