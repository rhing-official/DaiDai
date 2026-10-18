import 'package:flutter/material.dart';

import 'app_locale.dart';
import 'guide_content_fr.dart';

/// 使い方ガイド（初回の簡単な説明と、設定＞運営＞使い方ガイドの機能別解説）の
/// 文面（2026-10-17追加）。文面が長く数も多いため、`Strings`には載せずこの
/// ファイルに日英セットで持つ（`lib/l10n/`は日本語直書き禁止テストの対象外）。
/// 画面の部品名・ボタンの文言は`Strings`側にある。
///
/// 文面は実装済みの挙動に合わせて書いているが、ユーザーによるレビュー前の
/// 初稿。直すときはこのファイルだけを編集すればよい。
class GuideText {
  const GuideText(this.ja, this.en);

  final String ja;
  final String en;

  String of(AppLocale locale) => locale == AppLocale.japanese ? ja : en;
}

/// 日本語・英語以外の表示言語の訳。日本語・英語は[GuideText]自身が持つ。
/// 言語ごとに`guide_content_xx.dart`へ置き、[guideTranslationOf]のswitch式
/// （網羅性エラー）から返す。訳が無い項目は英語にフォールバックする。
class GuideTranslation {
  const GuideTranslation({required this.topics});

  /// 機能別ガイドの訳（[GuideTopic.id]→題・概要・手順）。
  final Map<String, GuideTopicText> topics;
}

class GuideTopicText {
  const GuideTopicText({
    required this.title,
    required this.summary,
    required this.steps,
  });

  final String title;
  final String summary;
  final List<String> steps;
}

/// 日本語・英語以外の表示言語のガイドの訳。
GuideTranslation? guideTranslationOf(AppLocale locale) {
  return switch (locale) {
    AppLocale.japanese => null,
    AppLocale.britishEnglish => null,
    AppLocale.french => guideTranslationFr,
  };
}

/// 機能別ガイドの1項目。[steps]は詳細画面に段落として並べる。
class GuideTopic {
  const GuideTopic({
    required this.id,
    required this.icon,
    required this.title,
    required this.summary,
    required this.steps,
    this.articleUrl,
  });

  final String id;
  final IconData icon;
  final GuideText title;
  final GuideText summary;
  final List<GuideText> steps;

  /// この機能の解説記事（noteなど）のURL。設定すると、使い方ガイドの一覧の項目に
  /// 「記事を読む」ボタンが出る。記事がまだ無い間は`null`（ボタンは出ない）。
  final String? articleUrl;

  String titleOf(AppLocale locale) =>
      _pick(locale, title, guideTranslationOf(locale)?.topics[id]?.title);

  String summaryOf(AppLocale locale) =>
      _pick(locale, summary, guideTranslationOf(locale)?.topics[id]?.summary);

  /// 手順の段落。訳の段落数が原文と違う場合は、ずれた内容を出さず英語にする。
  List<String> stepsOf(AppLocale locale) {
    final translated = guideTranslationOf(locale)?.topics[id]?.steps;
    if (locale == AppLocale.japanese) return [for (final s in steps) s.ja];
    if (translated != null && translated.length == steps.length) {
      return translated;
    }
    return [for (final s in steps) s.en];
  }
}

/// 日本語・英語はそれぞれの原文、それ以外は[translated]（無ければ英語）。
String _pick(AppLocale locale, GuideText text, String? translated) {
  if (locale == AppLocale.japanese) return text.ja;
  if (locale == AppLocale.britishEnglish) return text.en;
  return translated ?? text.en;
}

/// 機能別ガイド（設定＞運営＞使い方ガイドの一覧）。
const guideTopics = <GuideTopic>[
  GuideTopic(
    id: 'friends',
    icon: Icons.person_add_alt_1_outlined,
    title: GuideText('縁結び（友達を追加する）', 'Add Friend'),
    summary: GuideText(
      '招待リンクやQRコードで友達になります',
      'Connect using an invite link or QR code',
    ),
    steps: [
      GuideText(
        '「身だしなみ」の「縁結び」を開くと、自分の招待リンクとQRコードが表示されます。これを相手に送るか、相手に読み取ってもらいます。',
        'Open "Add Friend" in the Profile tab to see your invite link and QR code. Send it to someone, or let them scan it.',
      ),
      GuideText(
        '相手の招待リンクを開く、またはQRコードを読み取ると、友達申請を送れます。相手が承認すると、一対の語らいが始まります。',
        'Open someone else\'s invite link or scan their QR code to send a friend request. Once they accept, your Direct conversation begins.',
      ),
      GuideText(
        '招待リンクは、DaiDaiのメッセージに貼ると、プロフィールカードとして表示されます。',
        'If you paste an invite link into a DaiDai message, it shows up as a profile card.',
      ),
    ],
  ),
  GuideTopic(
    id: 'direct-plaza',
    icon: Icons.groups_outlined,
    title: GuideText('一対と広場', 'Direct and Plaza'),
    summary: GuideText(
      '1対1の会話と、みんなで集まる場所',
      'One-to-one chats and group spaces',
    ),
    steps: [
      GuideText(
        '「一対」は、友達と2人だけの会話です。「広場」は、3人以上が集まる場所で、作った人は「長」として管理します。',
        'A "Direct" is a private chat with one friend. A "Plaza" is a space for three or more people, managed by its Owner.',
      ),
      GuideText(
        '広場には、招待リンクで人を呼べます。参加に長の承認が必要かどうかは、広場の設定で選べます。',
        'Invite people to a Plaza with an invite link. The Owner chooses in the Plaza settings whether joining needs approval.',
      ),
      GuideText(
        '広場の「ロール」で、メンバーに管理の権限（寄合の管理・招待リンクの作成など）を分けて渡せます。',
        'Roles let the Owner share management permissions (managing channels, creating invite links, and so on) with members.',
      ),
    ],
  ),
  GuideTopic(
    id: 'rooms',
    icon: Icons.forum_outlined,
    title: GuideText('寄合（会話を分ける）', 'Text channels'),
    summary: GuideText(
      '一つの会話の中で話題ごとに場所を分けます',
      'Split one conversation into separate topics',
    ),
    steps: [
      GuideText(
        '一対でも広場でも、「寄合」を追加して話題ごとに会話を分けられます。最初は寄合が1つだけのシンプルな状態です。',
        'In both Directs and Plazas you can add text channels to separate topics. At first there is just one.',
      ),
      GuideText(
        '複数の寄合を使うには、会話の設定にある「寄合機能」をオンにします。オンにすると、寄合の一覧から追加・切り替えができます。',
        'To use several channels, turn on the channel feature in the conversation settings. You can then add and switch channels.',
      ),
    ],
  ),
  GuideTopic(
    id: 'messages',
    icon: Icons.send_outlined,
    title: GuideText('メッセージの送り方', 'Sending messages'),
    summary: GuideText(
      '文字・写真・ファイル・ぺったん・メンション',
      'Text, photos, files, stickers and mentions',
    ),
    steps: [
      GuideText(
        '文字のほか、写真・動画・ファイルを最大10件までまとめて送れます。',
        'Besides text, you can send up to 10 photos, videos or files in one message.',
      ),
      GuideText(
        '入力中の文字に合わせて、おすすめの「ぺったん」が入力欄の上に出ることがあります。',
        'While you type, suggested stickers may appear above the input field.',
      ),
      GuideText(
        '「@」を打つと、相手や「@everyone」を指定して通知できます。',
        'Type "@" to mention someone, or "@everyone" to notify the whole group.',
      ),
      GuideText(
        'メッセージを返信・ピン留めしたり、まとめて選んで削除したりできます。削除は自分の画面から消えるだけで、相手には残ります。全員が削除すると、サーバーからも消えます。',
        'You can reply to or pin messages, or select several to delete. Deleting only hides them for you; they are removed from the server once everyone has deleted them.',
      ),
    ],
  ),
  GuideTopic(
    id: 'notes',
    icon: Icons.edit_note_outlined,
    title: GuideText('ノート', 'Notes'),
    summary: GuideText('会話の中でメモを書きためます', 'Keep notes inside a conversation'),
    steps: [
      GuideText(
        '会話のメニューから「ノート」を開くと、文章・見出し・リスト・表などを書き残せます。',
        'Open "Notes" from the conversation menu to write text, headings, lists and tables.',
      ),
      GuideText(
        '「+」から表などのブロックを足せます。スマホでは、表のセルをタップすると行と列のハンドルが出て、長押しで並べ替えや範囲の選択ができます。',
        'Use "+" to add blocks such as tables. On phones, tap a table cell to show row and column handles; long-press to reorder or select a range.',
      ),
    ],
  ),
  GuideTopic(
    id: 'calendar',
    icon: Icons.calendar_month_outlined,
    title: GuideText('カレンダー', 'Calendar'),
    summary: GuideText('予定の共有と日程調整', 'Shared events and scheduling'),
    steps: [
      GuideText(
        '会話のメニューから「カレンダー」を開くと、予定を追加して共有できます。',
        'Open "Calendar" from the conversation menu to add and share events.',
      ),
      GuideText(
        '日程調整では、候補日を出して、みんなの都合を集められます。',
        'Scheduling lets you propose dates and gather everyone\'s availability.',
      ),
      GuideText(
        '設定の「アカウント」で、Googleカレンダーとの同期をオンにできます。',
        'In Settings > Account you can turn on sync with Google Calendar.',
      ),
    ],
  ),
  GuideTopic(
    id: 'album',
    icon: Icons.photo_library_outlined,
    title: GuideText('アルバム', 'Album'),
    summary: GuideText(
      '写真や動画を会話ごとに残します',
      'Keep photos and videos per conversation',
    ),
    steps: [
      GuideText(
        'メッセージの写真や動画は、アルバムに追加すると残せます。メッセージの保存期間が過ぎても、アルバムに入れたものは残ります。',
        'Add photos and videos from messages to the album to keep them, even after the message retention period.',
      ),
      GuideText(
        'アルバムは会話のメニューから開けます。',
        'Open the album from the conversation menu.',
      ),
    ],
  ),
  GuideTopic(
    id: 'calls',
    icon: Icons.videocam_outlined,
    title: GuideText('通話', 'Calls'),
    summary: GuideText('音声通話とビデオ通話', 'Voice and video calls'),
    steps: [
      GuideText(
        '一対でも広場でも、会話の画面から音声通話・ビデオ通話を始められます。',
        'Start a voice or video call from any Direct or Plaza.',
      ),
      GuideText(
        '通話中は、画面を小さくして他の画面を見ながら続けることもできます。',
        'During a call you can shrink the screen and keep going while you look at other things.',
      ),
    ],
  ),
  GuideTopic(
    id: 'profile',
    icon: Icons.badge_outlined,
    title: GuideText('身だしなみ（プロフィール）', 'Profile'),
    summary: GuideText(
      '蔵と仕立てで、自分のカードを整えます',
      'Shape your cards in the Material Box and Tailoring',
    ),
    steps: [
      GuideText(
        '「蔵」には、アイコン・背景画像・呼び名・一言などの素材をしまっておけます。',
        'The Material Box stores your icons, backgrounds, nicknames and status messages.',
      ),
      GuideText(
        '「仕立て」では、蔵の素材を組み合わせてプロフィールカードを作ります。カードは最大3枚まで作れ、友達や会話ごとに使い分けられます。',
        'In Tailoring you combine materials into profile cards. You can make up to three and use different ones per conversation.',
      ),
    ],
  ),
  GuideTopic(
    id: 'safety',
    icon: Icons.lock_outline,
    title: GuideText('安全とプライバシー', 'Safety and privacy'),
    summary: GuideText(
      'ブロック・絶縁・ログインの守り・アカウント削除',
      'Blocking, severing, sign-in protection and deleting your account',
    ),
    steps: [
      GuideText(
        '一対の相手を「ブロック」すると、その人のメッセージや申請が見えなくなります。相手にはブロックしたことが伝わりません。',
        'Blocking someone in a Direct hides their messages and requests. They are not told that you blocked them.',
      ),
      GuideText(
        '「絶縁」は、お互いの同意があるときに、一対の会話履歴を完全に消す機能です。',
        '"Sever" permanently deletes a Direct\'s history, but only when both people agree.',
      ),
      GuideText(
        '設定の「アカウント」で、2段階認証（認証アプリ）やパスキーを設定すると、ログインをより安全にできます。',
        'In Settings > Account you can set up two-step verification (authenticator app) and passkeys for safer sign-in.',
      ),
      GuideText(
        'アカウントを削除すると、30日間は復元できます。すぐに完全に消すこともできます。長を務める広場がある場合は、先に長を譲る必要があります。',
        'A deleted account can be restored for 30 days, or you can delete it immediately and permanently. If you own a Plaza, transfer ownership first.',
      ),
    ],
  ),
  GuideTopic(
    id: 'kiwami',
    icon: Icons.workspace_premium_outlined,
    title: GuideText('極み', 'Kiwami'),
    summary: GuideText(
      '一部の機能が広がる有料プラン',
      'A paid plan that unlocks extra features',
    ),
    steps: [
      GuideText(
        '「極み」は、既読の表示を隠せる、限定のフォントが使える、といった機能をまとめた有料プランです。既読を隠す設定は、会話に極みの人がいる間だけ効きます。',
        '"Kiwami" is a paid plan that bundles extras such as hiding read receipts and exclusive fonts. Hiding read receipts only takes effect while someone in the conversation has Kiwami.',
      ),
      GuideText(
        '購入の方法は準備中です。限定のフォントは、極みでない間は標準のフォントで表示されます。',
        'How to subscribe is coming soon. Until you have Kiwami, exclusive fonts are shown in the standard font.',
      ),
    ],
  ),
];
