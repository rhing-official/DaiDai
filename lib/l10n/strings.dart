import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_locale_provider.dart';
import 'app_locale.dart';

/// 表示文言の対訳表。現状は主要なナビゲーション・設定画面のみ対応し、
/// 残りは日本語のハードコードのまま（実装内容.mdの未実装項目を参照）。
class Strings {
  const Strings._({
    required this.navTalk,
    required this.navProfile,
    required this.navSettings,
    required this.navSupport,
    required this.talkCategoryDm,
    required this.talkCategoryGroup,
    required this.addMenuDmTitle,
    required this.addMenuDmSubtitle,
    required this.addMenuGroupTitle,
    required this.addMenuGroupSubtitle,
    required this.settingsFolderAccount,
    required this.settingsFolderDesign,
    required this.settingsFolderDisplayLanguage,
    required this.settingsFolderNotifications,
    required this.settingsAccentColor,
    required this.settingsColorCode,
    required this.settingsLogout,
    required this.settingsDisplayLanguage,
    required this.settingsTerminology,
    required this.settingsComingSoon,
    required this.back,
    required this.friendSearchTitle,
    required this.friendSearchHint,
    required this.friendSearchLabel,
    required this.friendSearchButton,
    required this.friendSearchNotFound,
    required this.friendSearchSelf,
    required this.friendRequestSent,
    required this.friendRequestAlreadySent,
    required this.friendRequestAlreadyFriends,
    required this.friendRequestAccept,
    required this.friendRequestDecline,
    required this.friendRequestIncomingSubtitle,
    required this.friendRequestOutgoingSubtitle,
    required this.conversationPin,
    required this.conversationUnpin,
    required this.conversationMute,
    required this.conversationUnmute,
  });

  final String navTalk;
  final String navProfile;
  final String navSettings;
  final String navSupport;

  final String talkCategoryDm;
  final String talkCategoryGroup;

  final String addMenuDmTitle;
  final String addMenuDmSubtitle;
  final String addMenuGroupTitle;
  final String addMenuGroupSubtitle;

  final String settingsFolderAccount;
  final String settingsFolderDesign;
  final String settingsFolderDisplayLanguage;
  final String settingsFolderNotifications;
  final String settingsAccentColor;
  final String settingsColorCode;
  final String settingsLogout;
  final String settingsDisplayLanguage;
  final String settingsTerminology;
  final String settingsComingSoon;

  final String back;

  final String friendSearchTitle;
  final String friendSearchHint;
  final String friendSearchLabel;
  final String friendSearchButton;
  final String friendSearchNotFound;
  final String friendSearchSelf;
  final String friendRequestSent;
  final String friendRequestAlreadySent;
  final String friendRequestAlreadyFriends;
  final String friendRequestAccept;
  final String friendRequestDecline;
  final String friendRequestIncomingSubtitle;
  final String friendRequestOutgoingSubtitle;
  final String conversationPin;
  final String conversationUnpin;
  final String conversationMute;
  final String conversationUnmute;

  static const ja = Strings._(
    navTalk: '語らい',
    navProfile: '身だしなみ',
    navSettings: '設定',
    navSupport: '運営',
    talkCategoryDm: '一対',
    talkCategoryGroup: '広場',
    addMenuDmTitle: '一対を始める',
    addMenuDmSubtitle: '1対1で話す相手を追加する',
    addMenuGroupTitle: '広場を作る',
    addMenuGroupSubtitle: '3人以上のグループを作る',
    settingsFolderAccount: 'アカウント',
    settingsFolderDesign: 'デザイン',
    settingsFolderDisplayLanguage: '表示・言語',
    settingsFolderNotifications: '通知',
    settingsAccentColor: 'アクセントカラー',
    settingsColorCode: 'カラーコード',
    settingsLogout: 'ログアウト',
    settingsDisplayLanguage: '表示言語',
    settingsTerminology: '用語・表示設定',
    settingsComingSoon: '準備中',
    back: '戻る',
    friendSearchTitle: '友達を追加',
    friendSearchHint: '相手のRhing IDを入力して友達申請を送ります。承認されると会話できるようになります。',
    friendSearchLabel: '相手のRhing ID',
    friendSearchButton: '申請を送る',
    friendSearchNotFound: 'そのRhing IDの住人は見つかりませんでした',
    friendSearchSelf: '自分自身には申請できません',
    friendRequestSent: '友達申請を送りました',
    friendRequestAlreadySent: 'すでに申請中です',
    friendRequestAlreadyFriends: 'すでに友達です',
    friendRequestAccept: '承認',
    friendRequestDecline: '拒否',
    friendRequestIncomingSubtitle: '相手から申請が届いています',
    friendRequestOutgoingSubtitle: '相手の承認を待っています',
    conversationPin: 'ピン留め',
    conversationUnpin: 'ピン留めを外す',
    conversationMute: '通知オフ',
    conversationUnmute: '通知オン',
  );

  static const enGB = Strings._(
    navTalk: 'Talks',
    navProfile: 'Profile',
    navSettings: 'Settings',
    navSupport: 'Support',
    talkCategoryDm: 'DMs',
    talkCategoryGroup: 'Squares',
    addMenuDmTitle: 'Start a DM',
    addMenuDmSubtitle: 'Add someone to talk to one-on-one',
    addMenuGroupTitle: 'Create a Square',
    addMenuGroupSubtitle: 'Make a group with three or more people',
    settingsFolderAccount: 'Account',
    settingsFolderDesign: 'Design',
    settingsFolderDisplayLanguage: 'Display & Language',
    settingsFolderNotifications: 'Notifications',
    settingsAccentColor: 'Accent colour',
    settingsColorCode: 'Colour code',
    settingsLogout: 'Log out',
    settingsDisplayLanguage: 'Display language',
    settingsTerminology: 'Terminology & display',
    settingsComingSoon: 'Coming soon',
    back: 'Back',
    friendSearchTitle: 'Add a friend',
    friendSearchHint:
        "Enter the other person's Rhing ID to send a friend request. "
        'Once accepted, you can start talking.',
    friendSearchLabel: "Their Rhing ID",
    friendSearchButton: 'Send request',
    friendSearchNotFound: 'No resident found with that Rhing ID',
    friendSearchSelf: "You can't send a request to yourself",
    friendRequestSent: 'Friend request sent',
    friendRequestAlreadySent: 'Request already pending',
    friendRequestAlreadyFriends: 'Already friends',
    friendRequestAccept: 'Accept',
    friendRequestDecline: 'Decline',
    friendRequestIncomingSubtitle: 'They sent you a friend request',
    friendRequestOutgoingSubtitle: 'Waiting for them to accept',
    conversationPin: 'Pin',
    conversationUnpin: 'Unpin',
    conversationMute: 'Mute notifications',
    conversationUnmute: 'Unmute notifications',
  );

  static Strings of(AppLocale locale) => switch (locale) {
    AppLocale.japanese => ja,
    AppLocale.britishEnglish => enGB,
  };
}

/// 現在の表示言語に対応する対訳セット。
final appStringsProvider = Provider<Strings>((ref) {
  return Strings.of(ref.watch(appLocaleProvider));
});
