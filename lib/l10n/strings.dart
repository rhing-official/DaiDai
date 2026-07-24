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
    required this.addMenuDmTitleTemplate,
    required this.addMenuDmSubtitle,
    required this.addMenuGroupTitleTemplate,
    required this.addMenuGroupSubtitle,
    required this.settingsFolderAccount,
    required this.settingsFolderApplication,
    required this.settingsFolderDesign,
    required this.settingsFolderLanguage,
    required this.settingsFolderInput,
    required this.settingsFolderNotifications,
    required this.settingsAccentColor,
    required this.settingsColorCode,
    required this.settingsColorPresets,
    required this.settingsLogout,
    required this.settingsDisplayLanguage,
    required this.settingsTerminology,
    required this.settingsTerminologyWorldview,
    required this.settingsTerminologyConvenience,
    required this.settingsSubUI,
    required this.settingsUIDescription,
    required this.settingsSubTypography,
    required this.settingsFontDesign,
    required this.settingsFontSize,
    required this.settingsRhingIdLabel,
    required this.settingsProfileName,
    required this.settingsSecurity,
    required this.settingsPassword,
    required this.settingsTwoFactor,
    required this.settingsPasskey,
    required this.settingsQrLogin,
    required this.settingsDeleteAccount,
    required this.settingsComingSoon,
    required this.supportHomepageUrl,
    required this.supportAnnouncements,
    required this.supportContactForm,
    required this.plazaCurrentTypeSubtitle,
    required this.plazaTextChannelSubtitle,
    required this.plazaPublicPlazaSubtitle,
    required this.settingsSendKeyTitle,
    required this.settingsSendKeyEnterToSend,
    required this.settingsSendKeyCtrlEnterToSend,
    required this.settingsSendKeySilentEnterToSend,
    required this.settingsSendKeySilentCtrlEnterToSend,
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
    required this.cancel,
    required this.add,
    required this.save,
    required this.profileIconSection,
    required this.profileBackgroundSection,
    required this.profileNicknameSection,
    required this.profileNicknameHint,
    required this.profileStatusMessageSection,
    required this.profileAddNickname,
    required this.profileAddStatusMessage,
    required this.profileNicknameDialogTitle,
    required this.profileNicknameDialogEditTitle,
    required this.profileNicknameDialogHint,
    required this.profileStatusMessageDialogTitle,
    required this.profileStatusMessageDialogEditTitle,
    required this.profileStatusMessageDialogHint,
    required this.profileSaveError,
    required this.profileIconUploadError,
    required this.profileBackgroundUploadError,
    required this.workshopDescriptionTemplate,
    required this.workshopCardNameLabel,
    required this.workshopCardDialogTitleNew,
    required this.workshopCardDialogTitleEdit,
    required this.workshopFieldIcon,
    required this.workshopFieldBackground,
    required this.workshopFieldNickname,
    required this.workshopFieldStatusMessage,
    required this.workshopChoiceNone,
    required this.workshopChoiceSelected,
    required this.workshopChoiceSelect,
    required this.workshopEmptyMaterialHint,
    required this.workshopNameRequiredHint,
    required this.workshopEditNameTooltip,
    required this.workshopDeleteCardTooltip,
    required this.workshopCloseTooltip,
    required this.fieldRequiredError,
  });

  final String navTalk;
  final String navProfile;
  final String navSettings;
  final String navSupport;

  /// 一対/DM等の用語を差し込んだタイトルを組み立てる（例: 「一対を始める」）。
  final String Function(String dmTerm) addMenuDmTitleTemplate;
  final String addMenuDmSubtitle;

  /// 広場/Server等の用語を差し込んだタイトルを組み立てる（例: 「広場を作る」）。
  final String Function(String plazaTerm) addMenuGroupTitleTemplate;
  final String addMenuGroupSubtitle;

  final String settingsFolderAccount;
  final String settingsFolderApplication;
  final String settingsFolderDesign;
  final String settingsFolderLanguage;
  final String settingsFolderInput;
  final String settingsFolderNotifications;
  final String settingsAccentColor;
  final String settingsColorCode;
  final String settingsColorPresets;
  final String settingsLogout;
  final String settingsDisplayLanguage;
  final String settingsTerminology;
  final String settingsTerminologyWorldview;
  final String settingsTerminologyConvenience;
  final String settingsSubUI;
  final String settingsUIDescription;
  final String settingsSubTypography;
  final String settingsFontDesign;
  final String settingsFontSize;
  final String settingsRhingIdLabel;
  final String settingsProfileName;
  final String settingsSecurity;
  final String settingsPassword;
  final String settingsTwoFactor;
  final String settingsPasskey;
  final String settingsQrLogin;
  final String settingsDeleteAccount;
  final String settingsComingSoon;
  final String settingsSendKeyTitle;
  final String settingsSendKeyEnterToSend;
  final String settingsSendKeyCtrlEnterToSend;
  final String settingsSendKeySilentEnterToSend;
  final String settingsSendKeySilentCtrlEnterToSend;

  final String supportHomepageUrl;
  final String supportAnnouncements;
  final String supportContactForm;

  final String plazaCurrentTypeSubtitle;
  final String plazaTextChannelSubtitle;
  final String plazaPublicPlazaSubtitle;

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

  final String cancel;
  final String add;
  final String save;

  final String profileIconSection;
  final String profileBackgroundSection;
  final String profileNicknameSection;
  final String profileNicknameHint;
  final String profileStatusMessageSection;
  final String profileAddNickname;
  final String profileAddStatusMessage;
  final String profileNicknameDialogTitle;
  final String profileNicknameDialogEditTitle;
  final String profileNicknameDialogHint;
  final String profileStatusMessageDialogTitle;
  final String profileStatusMessageDialogEditTitle;
  final String profileStatusMessageDialogHint;
  final String profileSaveError;
  final String profileIconUploadError;
  final String profileBackgroundUploadError;

  /// 蔵/Storehouse等の用語を差し込んだ説明文を組み立てる。
  final String Function(String profileStorageTerm) workshopDescriptionTemplate;
  final String workshopCardNameLabel;
  final String workshopCardDialogTitleNew;
  final String workshopCardDialogTitleEdit;
  final String workshopFieldIcon;
  final String workshopFieldBackground;
  final String workshopFieldNickname;
  final String workshopFieldStatusMessage;
  final String workshopChoiceNone;
  final String workshopChoiceSelected;
  final String workshopChoiceSelect;
  final String workshopEmptyMaterialHint;
  final String workshopNameRequiredHint;
  final String workshopEditNameTooltip;
  final String workshopDeleteCardTooltip;
  final String workshopCloseTooltip;
  final String fieldRequiredError;

  static final ja = Strings._(
    navTalk: '語らい',
    navProfile: '身だしなみ',
    navSettings: '設定',
    navSupport: '運営',
    addMenuDmTitleTemplate: (dmTerm) => '$dmTermを始める',
    addMenuDmSubtitle: '1対1で話す相手を追加する',
    addMenuGroupTitleTemplate: (plazaTerm) => '$plazaTermを作る',
    addMenuGroupSubtitle: '3人以上のグループを作る',
    settingsFolderAccount: 'アカウント',
    settingsFolderApplication: 'アプリケーション',
    settingsFolderDesign: '色',
    settingsFolderLanguage: '言語',
    settingsFolderInput: '入力',
    settingsFolderNotifications: '通知',
    settingsAccentColor: 'アクセントカラー',
    settingsColorCode: 'カラーコード',
    settingsColorPresets: 'プリセット',
    settingsLogout: 'ログアウト',
    settingsDisplayLanguage: '表示言語',
    settingsTerminology: '用語・表示設定',
    settingsTerminologyWorldview: '世界観重視',
    settingsTerminologyConvenience: '利便性重視',
    settingsSubUI: 'UI',
    settingsUIDescription:
        '現在のUIスタイルは「シンプル」1本に統一されています（切り替え機能は今後の検討事項です）。',
    settingsSubTypography: '文字',
    settingsFontDesign: 'フォントデザイン',
    settingsFontSize: 'フォントサイズ',
    settingsRhingIdLabel: 'Rhing ID',
    settingsProfileName: 'プロフィール名',
    settingsSecurity: 'セキュリティ',
    settingsPassword: 'パスワード',
    settingsTwoFactor: '2段階認証',
    settingsPasskey: 'パスキー',
    settingsQrLogin: 'QRコードによるログイン',
    settingsDeleteAccount: 'アカウントの削除',
    settingsComingSoon: '準備中',
    settingsSendKeyTitle: 'メッセージの送信キー',
    settingsSendKeyEnterToSend: 'Enterで送信、Shift+Enterで改行',
    settingsSendKeyCtrlEnterToSend: 'Enterで改行、Ctrl+Enterで送信',
    settingsSendKeySilentEnterToSend: 'Ctrl+Enterで相手に通知せず送信',
    settingsSendKeySilentCtrlEnterToSend: 'Ctrl+Shift+Enterで相手に通知せず送信',
    supportHomepageUrl: 'ホームページのURL',
    supportAnnouncements: 'お知らせ',
    supportContactForm: '質問フォーム',
    plazaCurrentTypeSubtitle: '現在この広場は非公開（裏広場）です',
    plazaTextChannelSubtitle: '今の会話がこれにあたります',
    plazaPublicPlazaSubtitle: '不特定多数が参加できる広場です（フェーズ3で対応予定）',
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
    cancel: 'キャンセル',
    add: '追加',
    save: '保存',
    profileIconSection: 'アイコン',
    profileBackgroundSection: '背景画像',
    profileNicknameSection: 'ニックネーム',
    profileNicknameHint: '友達には、Rhing IDの代わりにここで選んだニックネームが表示されます。',
    profileStatusMessageSection: 'ステメ',
    profileAddNickname: 'ニックネームを追加',
    profileAddStatusMessage: 'ステメを追加',
    profileNicknameDialogTitle: 'ニックネームを追加',
    profileNicknameDialogEditTitle: 'ニックネームを編集',
    profileNicknameDialogHint: '友達に表示する呼び名を入力',
    profileStatusMessageDialogTitle: 'ステメを追加',
    profileStatusMessageDialogEditTitle: 'ステメを編集',
    profileStatusMessageDialogHint: 'ひとことを入力',
    profileSaveError: '保存に失敗しました',
    profileIconUploadError: 'アイコンのアップロードに失敗しました',
    profileBackgroundUploadError: '背景画像のアップロードに失敗しました',
    workshopDescriptionTemplate: (term) =>
        '$termに登録した素材を組み合わせて、プロフィールカードを作れます。カードをタップして編集してください。',
    workshopCardNameLabel: 'カード名（自分用のラベル）',
    workshopCardDialogTitleNew: 'プロフィールカードを作る',
    workshopCardDialogTitleEdit: 'プロフィールカードを編集',
    workshopFieldIcon: 'アイコン',
    workshopFieldBackground: '背景画像',
    workshopFieldNickname: 'ニックネーム',
    workshopFieldStatusMessage: 'ステメ',
    workshopChoiceNone: 'なし',
    workshopChoiceSelected: '選択中',
    workshopChoiceSelect: '選ぶ',
    workshopEmptyMaterialHint: '蔵に素材が登録されていません',
    workshopNameRequiredHint: '先にカード名を入力してください',
    workshopEditNameTooltip: 'カード名を編集',
    workshopDeleteCardTooltip: 'カードを削除',
    workshopCloseTooltip: '閉じる',
    fieldRequiredError: '入力してください',
  );

  static final enGB = Strings._(
    navTalk: 'Talks',
    navProfile: 'Profile',
    navSettings: 'Settings',
    navSupport: 'Support',
    addMenuDmTitleTemplate: (dmTerm) => 'Start a $dmTerm',
    addMenuDmSubtitle: 'Add someone to talk to one-on-one',
    addMenuGroupTitleTemplate: (plazaTerm) => 'Create a $plazaTerm',
    addMenuGroupSubtitle: 'Make a group with three or more people',
    settingsFolderAccount: 'Account',
    settingsFolderApplication: 'Application',
    settingsFolderDesign: 'Colour',
    settingsFolderLanguage: 'Language',
    settingsFolderInput: 'Input',
    settingsFolderNotifications: 'Notifications',
    settingsAccentColor: 'Accent colour',
    settingsColorCode: 'Colour code',
    settingsColorPresets: 'Presets',
    settingsLogout: 'Log out',
    settingsDisplayLanguage: 'Display language',
    settingsTerminology: 'Terminology & display',
    settingsTerminologyWorldview: 'Worldview-focused',
    settingsTerminologyConvenience: 'Convenience-focused',
    settingsSubUI: 'UI',
    settingsUIDescription:
        'The current UI style is fixed to "Simple" (a style switcher may '
        'be added in the future).',
    settingsSubTypography: 'Typography',
    settingsFontDesign: 'Font design',
    settingsFontSize: 'Font size',
    settingsRhingIdLabel: 'Rhing ID',
    settingsProfileName: 'Profile name',
    settingsSecurity: 'Security',
    settingsPassword: 'Password',
    settingsTwoFactor: 'Two-factor authentication',
    settingsPasskey: 'Passkey',
    settingsQrLogin: 'Sign in with a QR code',
    settingsDeleteAccount: 'Delete account',
    settingsComingSoon: 'Coming soon',
    settingsSendKeyTitle: 'Message send key',
    settingsSendKeyEnterToSend: 'Enter to send, Shift+Enter for a new line',
    settingsSendKeyCtrlEnterToSend: 'Enter for a new line, Ctrl+Enter to send',
    settingsSendKeySilentEnterToSend:
        'Ctrl+Enter to send without notifying the recipient',
    settingsSendKeySilentCtrlEnterToSend:
        'Ctrl+Shift+Enter to send without notifying the recipient',
    supportHomepageUrl: 'Homepage URL',
    supportAnnouncements: 'Announcements',
    supportContactForm: 'Contact form',
    plazaCurrentTypeSubtitle: 'This Plaza is currently private',
    plazaTextChannelSubtitle: 'Your current conversation is this',
    plazaPublicPlazaSubtitle:
        'A plaza anyone can join (planned for a later phase)',
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
    cancel: 'Cancel',
    add: 'Add',
    save: 'Save',
    profileIconSection: 'Icons',
    profileBackgroundSection: 'Background images',
    profileNicknameSection: 'Nicknames',
    profileNicknameHint:
        "Friends see the nickname you've selected here instead of your Rhing ID.",
    profileStatusMessageSection: 'Status messages',
    profileAddNickname: 'Add a nickname',
    profileAddStatusMessage: 'Add a status message',
    profileNicknameDialogTitle: 'Add a nickname',
    profileNicknameDialogEditTitle: 'Edit nickname',
    profileNicknameDialogHint: 'Enter the name shown to friends',
    profileStatusMessageDialogTitle: 'Add a status message',
    profileStatusMessageDialogEditTitle: 'Edit status message',
    profileStatusMessageDialogHint: 'Enter a short status message',
    profileSaveError: 'Failed to save',
    profileIconUploadError: 'Failed to upload icon',
    profileBackgroundUploadError: 'Failed to upload background image',
    workshopDescriptionTemplate: (term) =>
        'Combine materials from your $term into profile cards. '
        'Tap a card to edit it.',
    workshopCardNameLabel: 'Card name (private label for you)',
    workshopCardDialogTitleNew: 'Create a profile card',
    workshopCardDialogTitleEdit: 'Edit profile card',
    workshopFieldIcon: 'Icon',
    workshopFieldBackground: 'Background image',
    workshopFieldNickname: 'Nickname',
    workshopFieldStatusMessage: 'Status message',
    workshopChoiceNone: 'None',
    workshopChoiceSelected: 'Selected',
    workshopChoiceSelect: 'Select',
    workshopEmptyMaterialHint: 'Nothing registered in your storehouse yet',
    workshopNameRequiredHint: 'Enter a card name first',
    workshopEditNameTooltip: 'Edit card name',
    workshopDeleteCardTooltip: 'Delete card',
    workshopCloseTooltip: 'Close',
    fieldRequiredError: 'Please enter a value',
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
