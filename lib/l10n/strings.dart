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
    required this.settingsFolderTalk,
    required this.settingsBlockedUsersTitle,
    required this.settingsBlockedUsersEmpty,
    required this.settingsBlockedUsersUnblock,
    required this.settingsAccentColor,
    required this.settingsColorCode,
    required this.settingsColorPresets,
    required this.settingsLogout,
    required this.settingsDisplayLanguage,
    required this.settingsTerminology,
    required this.settingsTerminologyWorldview,
    required this.settingsTerminologyConvenience,
    required this.settingsTimeFormat,
    required this.settingsTimeFormat24h,
    required this.settingsTimeFormat12h,
    required this.settingsSubUI,
    required this.settingsUIDescription,
    required this.settingsChatLayoutTitle,
    required this.settingsChatLayoutSideBySide,
    required this.settingsChatLayoutSideBySideDescription,
    required this.settingsChatLayoutAllLeft,
    required this.settingsChatLayoutAllLeftDescription,
    required this.settingsSubTypography,
    required this.settingsFontDesign,
    required this.settingsFontSize,
    required this.settingsAccountInfoSection,
    required this.settingsRhingIdLabel,
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
    required this.conversationBlock,
    required this.conversationUnblock,
    required this.conversationBlockedCannotSend,
    required this.conversationReadReceiptsDisable,
    required this.conversationReadReceiptsEnable,
    required this.readReceiptPopupTitle,
    required this.cancel,
    required this.add,
    required this.save,
    required this.done,
    required this.delete,
    required this.profileIconSection,
    required this.profileBackgroundSection,
    required this.profileNicknameHint,
    required this.profileAddNickname,
    required this.profileAddStatusMessage,
    required this.profileNicknameDialogTitle,
    required this.profileNicknameDialogEditTitle,
    required this.profileNicknameDialogHint,
    required this.profileStatusMessageDialogTitle,
    required this.profileStatusMessageDialogEditTitle,
    required this.profileStatusMessageDialogHint,
    required this.profileSnsLinkSectionTitle,
    required this.profileAddSnsLink,
    required this.profileSnsLinkDialogTitle,
    required this.profileSnsLinkDialogEditTitle,
    required this.profileSnsLinkDialogHint,
    required this.profileSnsLinkInvalidError,
    required this.workshopSnsLinkFieldLabel,
    required this.profileSaveError,
    required this.profileIconUploadError,
    required this.profileBackgroundUploadError,
    required this.workshopCardNameLabel,
    required this.workshopCardDialogTitleNew,
    required this.workshopCardDialogTitleEdit,
    required this.workshopFieldIcon,
    required this.workshopFieldBackground,
    required this.workshopChoiceNone,
    required this.workshopChoiceSelected,
    required this.workshopChoiceSelect,
    required this.workshopEmptyMaterialHint,
    required this.fieldRequiredError,
    required this.enmusubiInviteLinkTitle,
    required this.enmusubiInviteLinkDescription,
    required this.enmusubiCopyLink,
    required this.enmusubiQrTitle,
    required this.enmusubiQrDescription,
    required this.enmusubiScanButton,
    required this.enmusubiScanScreenTitle,
    required this.inviteScreenTitle,
    required this.inviteConfirmDescriptionTemplate,
    required this.inviteScreenSendButton,
    required this.inviteScreenGoHome,
    required this.inviteScreenInvalid,
    required this.groupMenuProfileCard,
    required this.groupMenuMemberList,
    required this.groupMenuCreateInvite,
    required this.groupMenuLeave,
    required this.groupProfileCardNameLabel,
    required this.groupProfileCardDescriptionLabel,
    required this.groupMemberListTitle,
    required this.groupMemberListPendingSection,
    required this.groupMemberListMembersSection,
    required this.groupRoleModerator,
    required this.groupRoleMember,
    required this.groupInviteDialogTitle,
    required this.groupInviteDialogDescription,
    required this.groupLeaveConfirmTitle,
    required this.groupLeaveConfirmMessage,
    required this.groupLeaveButton,
    required this.groupLeaveOwnerError,
    required this.groupJoinScreenTitle,
    required this.groupJoinInvalid,
    required this.groupJoinAlreadyMember,
    required this.groupJoinPending,
    required this.groupJoinDescriptionTemplate,
    required this.groupJoinRequestButton,
    required this.groupJoinRequestSent,
    required this.groupJoinOpenGroup,
    required this.groupJoinRetry,
    required this.groupJoinPendingListSubtitle,
    required this.groupJoinPendingDialogClose,
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
  final String settingsFolderTalk;
  final String settingsBlockedUsersTitle;
  final String settingsBlockedUsersEmpty;
  final String settingsBlockedUsersUnblock;
  final String settingsAccentColor;
  final String settingsColorCode;
  final String settingsColorPresets;
  final String settingsLogout;
  final String settingsDisplayLanguage;
  final String settingsTerminology;
  final String settingsTerminologyWorldview;
  final String settingsTerminologyConvenience;
  final String settingsTimeFormat;
  final String settingsTimeFormat24h;
  final String settingsTimeFormat12h;
  final String settingsSubUI;
  final String settingsUIDescription;
  final String settingsChatLayoutTitle;
  final String settingsChatLayoutSideBySide;
  final String settingsChatLayoutSideBySideDescription;
  final String settingsChatLayoutAllLeft;
  final String settingsChatLayoutAllLeftDescription;
  final String settingsSubTypography;
  final String settingsFontDesign;
  final String settingsFontSize;
  final String settingsAccountInfoSection;
  final String settingsRhingIdLabel;
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
  final String conversationBlock;
  final String conversationUnblock;
  final String conversationBlockedCannotSend;
  final String conversationReadReceiptsDisable;
  final String conversationReadReceiptsEnable;
  final String readReceiptPopupTitle;

  final String cancel;
  final String add;
  final String save;
  final String done;
  final String delete;

  final String profileIconSection;
  final String profileBackgroundSection;

  /// ニックネーム欄の説明文。用語（呼び名／ニックネーム）を差し込む。
  final String Function(String nicknameTerm) profileNicknameHint;
  final String Function(String nicknameTerm) profileAddNickname;
  final String Function(String statusMessageTerm) profileAddStatusMessage;
  final String Function(String nicknameTerm) profileNicknameDialogTitle;
  final String Function(String nicknameTerm) profileNicknameDialogEditTitle;
  final String Function(String nicknameTerm) profileNicknameDialogHint;
  final String Function(String statusMessageTerm)
      profileStatusMessageDialogTitle;
  final String Function(String statusMessageTerm)
      profileStatusMessageDialogEditTitle;
  final String Function(String statusMessageTerm)
      profileStatusMessageDialogHint;
  final String profileSnsLinkSectionTitle;
  final String profileAddSnsLink;
  final String profileSnsLinkDialogTitle;
  final String profileSnsLinkDialogEditTitle;
  final String profileSnsLinkDialogHint;
  final String profileSnsLinkInvalidError;
  final String workshopSnsLinkFieldLabel;
  final String profileSaveError;
  final String profileIconUploadError;
  final String profileBackgroundUploadError;
  final String workshopCardNameLabel;
  final String workshopCardDialogTitleNew;
  final String workshopCardDialogTitleEdit;
  final String workshopFieldIcon;
  final String workshopFieldBackground;
  final String workshopChoiceNone;
  final String workshopChoiceSelected;
  final String workshopChoiceSelect;
  final String workshopEmptyMaterialHint;
  final String fieldRequiredError;

  final String enmusubiInviteLinkTitle;
  final String enmusubiInviteLinkDescription;
  final String enmusubiCopyLink;
  final String enmusubiQrTitle;
  final String enmusubiQrDescription;
  final String enmusubiScanButton;
  final String enmusubiScanScreenTitle;

  final String inviteScreenTitle;

  /// 招待リンク/QRコードから開いた確認画面の説明文。相手のRhing IDを差し込む。
  final String Function(String rhingId) inviteConfirmDescriptionTemplate;
  final String inviteScreenSendButton;
  final String inviteScreenGoHome;
  final String inviteScreenInvalid;

  final String groupMenuProfileCard;
  final String groupMenuMemberList;
  final String groupMenuCreateInvite;
  final String groupMenuLeave;

  final String groupProfileCardNameLabel;
  final String groupProfileCardDescriptionLabel;

  final String groupMemberListTitle;
  final String groupMemberListPendingSection;
  final String groupMemberListMembersSection;
  final String groupRoleModerator;
  final String groupRoleMember;

  final String groupInviteDialogTitle;
  final String groupInviteDialogDescription;

  final String groupLeaveConfirmTitle;
  final String groupLeaveConfirmMessage;
  final String groupLeaveButton;
  final String groupLeaveOwnerError;

  final String groupJoinScreenTitle;
  final String groupJoinInvalid;
  final String groupJoinAlreadyMember;
  final String groupJoinPending;

  /// 参加確認画面の説明文。広場名を差し込む。
  final String Function(String groupName) groupJoinDescriptionTemplate;
  final String groupJoinRequestButton;
  final String groupJoinRequestSent;
  final String groupJoinOpenGroup;
  final String groupJoinRetry;
  final String groupJoinPendingListSubtitle;
  final String groupJoinPendingDialogClose;

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
    settingsFolderTalk: '語らい',
    settingsBlockedUsersTitle: 'ブロックしたユーザー',
    settingsBlockedUsersEmpty: 'ブロックしたユーザーはいません',
    settingsBlockedUsersUnblock: 'ブロック解除',
    settingsAccentColor: 'アクセントカラー',
    settingsColorCode: 'カラーコード',
    settingsColorPresets: 'プリセット',
    settingsLogout: 'ログアウト',
    settingsDisplayLanguage: '表示言語',
    settingsTerminology: '用語・表示設定',
    settingsTerminologyWorldview: '世界観重視',
    settingsTerminologyConvenience: '利便性重視',
    settingsTimeFormat: 'メッセージの時刻表示',
    settingsTimeFormat24h: '24時間表記（00:00）',
    settingsTimeFormat12h: '12時間表記（12:00 p.m.）',
    settingsSubUI: 'UI',
    settingsUIDescription:
        '現在のUIスタイルは「シンプル」1本に統一されています（切り替え機能は今後の検討事項です）。',
    settingsChatLayoutTitle: '語らいの表示',
    settingsChatLayoutSideBySide: '自分は右・相手は左',
    settingsChatLayoutSideBySideDescription:
        '自分のアイコンは表示しません。一対では相手のアイコン・呼び名も表示しません（広場では表示します）。'
        'この設定は自分の画面にのみ反映され、相手の語らいの表示には影響しません。',
    settingsChatLayoutAllLeft: 'どちらも左寄せ',
    settingsChatLayoutAllLeftDescription:
        '自分・相手ともにアイコンと呼び名を表示します。'
        'この設定は自分の画面にのみ反映され、相手の語らいの表示には影響しません。',
    settingsSubTypography: '文字',
    settingsFontDesign: 'フォントデザイン',
    settingsFontSize: 'フォントサイズ',
    settingsAccountInfoSection: 'アカウント情報',
    settingsRhingIdLabel: 'Rhing ID',
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
    conversationBlock: 'ブロック',
    conversationUnblock: 'ブロック解除',
    conversationBlockedCannotSend: 'ブロック中のため送信できません',
    conversationReadReceiptsDisable: '既読オフ',
    conversationReadReceiptsEnable: '既読オン',
    readReceiptPopupTitle: '既読',
    cancel: 'キャンセル',
    add: '追加',
    save: '保存',
    done: '完了',
    delete: '削除',
    profileIconSection: 'アイコン',
    profileBackgroundSection: '背景画像',
    profileNicknameHint: (term) =>
        '友達には、Rhing IDの代わりにここで選んだ$termが表示されます。',
    profileAddNickname: (term) => '$termを追加',
    profileAddStatusMessage: (term) => '$termを追加',
    profileNicknameDialogTitle: (term) => '$termを追加',
    profileNicknameDialogEditTitle: (term) => '$termを編集',
    profileNicknameDialogHint: (term) => '友達に表示する$termを入力',
    profileStatusMessageDialogTitle: (term) => '$termを追加',
    profileStatusMessageDialogEditTitle: (term) => '$termを編集',
    profileStatusMessageDialogHint: (term) => '$termを入力',
    profileSnsLinkSectionTitle: 'SNSのURL',
    profileAddSnsLink: 'URLを追加',
    profileSnsLinkDialogTitle: 'URLを追加',
    profileSnsLinkDialogEditTitle: 'URLを編集',
    profileSnsLinkDialogHint: 'https://...',
    profileSnsLinkInvalidError: 'URLの形式が正しくありません',
    workshopSnsLinkFieldLabel: 'URL',
    profileSaveError: '保存に失敗しました',
    profileIconUploadError: 'アイコンのアップロードに失敗しました',
    profileBackgroundUploadError: '背景画像のアップロードに失敗しました',
    workshopCardNameLabel: 'カード名（自分用のラベル）',
    workshopCardDialogTitleNew: 'プロフィールカードを作る',
    workshopCardDialogTitleEdit: 'プロフィールカードを編集',
    workshopFieldIcon: 'アイコン',
    workshopFieldBackground: '背景画像',
    workshopChoiceNone: 'なし',
    workshopChoiceSelected: '選択中',
    workshopChoiceSelect: '選ぶ',
    workshopEmptyMaterialHint: '蔵に素材が登録されていません',
    fieldRequiredError: '入力してください',
    enmusubiInviteLinkTitle: '招待リンク',
    enmusubiInviteLinkDescription:
        'このリンクを知っている住人が開くと、あなたに仲間申請を送れます。',
    enmusubiCopyLink: 'コピー',
    enmusubiQrTitle: 'QRコードで交換',
    enmusubiQrDescription: '対面でQRコードを読み取ると、素早く仲間になれます。',
    enmusubiScanButton: 'QRコードを読み取る',
    enmusubiScanScreenTitle: 'QRコードを読み取る',
    inviteScreenTitle: '仲間申請',
    inviteConfirmDescriptionTemplate: (rhingId) =>
        '@$rhingIdの住人に仲間申請を送りますか？',
    inviteScreenSendButton: '仲間申請を送る',
    inviteScreenGoHome: 'ホームに戻る',
    inviteScreenInvalid: 'このリンクは無効です',
    groupMenuProfileCard: 'プロフィールカード',
    groupMenuMemberList: 'メンバー一覧',
    groupMenuCreateInvite: '招待リンク作成',
    groupMenuLeave: '退会',
    groupProfileCardNameLabel: '広場名',
    groupProfileCardDescriptionLabel: '一言',
    groupMemberListTitle: 'メンバー一覧',
    groupMemberListPendingSection: '参加リクエスト',
    groupMemberListMembersSection: 'メンバー',
    groupRoleModerator: 'モデレーター',
    groupRoleMember: 'メンバー',
    groupInviteDialogTitle: '招待リンク',
    groupInviteDialogDescription:
        'このリンクを知っている人が開くと、長・モデレーターの承認を経てこの広場に参加できます。',
    groupLeaveConfirmTitle: '広場から退会しますか？',
    groupLeaveConfirmMessage: '退会すると、この広場のメッセージは見られなくなります。',
    groupLeaveButton: '退会する',
    groupLeaveOwnerError: '長（オーナー）は退会できません',
    groupJoinScreenTitle: '広場への参加',
    groupJoinInvalid: 'この招待リンクは無効です',
    groupJoinAlreadyMember: '既にこの広場のメンバーです',
    groupJoinPending: '参加リクエストを送信済みです。長・モデレーターの承認をお待ちください',
    groupJoinDescriptionTemplate: (groupName) =>
        '「$groupName」への参加をリクエストしますか？長・モデレーターが承認すると参加できます。',
    groupJoinRequestButton: '参加をリクエストする',
    groupJoinRequestSent: '参加リクエストを送信しました。長・モデレーターの承認をお待ちください',
    groupJoinOpenGroup: '広場を開く',
    groupJoinRetry: '再読み込み',
    groupJoinPendingListSubtitle: '申請中・承認待ち',
    groupJoinPendingDialogClose: '閉じる',
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
    settingsFolderTalk: 'Talk',
    settingsBlockedUsersTitle: 'Blocked users',
    settingsBlockedUsersEmpty: 'No blocked users',
    settingsBlockedUsersUnblock: 'Unblock',
    settingsAccentColor: 'Accent colour',
    settingsColorCode: 'Colour code',
    settingsColorPresets: 'Presets',
    settingsLogout: 'Log out',
    settingsDisplayLanguage: 'Display language',
    settingsTerminology: 'Terminology & display',
    settingsTerminologyWorldview: 'Worldview-focused',
    settingsTerminologyConvenience: 'Convenience-focused',
    settingsTimeFormat: 'Message time display',
    settingsTimeFormat24h: '24-hour (00:00)',
    settingsTimeFormat12h: '12-hour (12:00 p.m.)',
    settingsSubUI: 'UI',
    settingsUIDescription:
        'The current UI style is fixed to "Simple" (a style switcher may '
        'be added in the future).',
    settingsChatLayoutTitle: 'Chat display',
    settingsChatLayoutSideBySide: 'You on the right, others on the left',
    settingsChatLayoutSideBySideDescription:
        "Hides your own avatar. In a direct message, also hides the other "
        "person's avatar and nickname (still shown in group chats). "
        "This only changes your own screen, not how others see the chat.",
    settingsChatLayoutAllLeft: 'Everyone on the left',
    settingsChatLayoutAllLeftDescription:
        'Always shows both your own and the other person\'s avatar and '
        'nickname. This only changes your own screen, not how others see '
        'the chat.',
    settingsSubTypography: 'Typography',
    settingsFontDesign: 'Font design',
    settingsFontSize: 'Font size',
    settingsAccountInfoSection: 'Account information',
    settingsRhingIdLabel: 'Rhing ID',
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
    conversationBlock: 'Block',
    conversationUnblock: 'Unblock',
    conversationBlockedCannotSend: "You can't send messages while blocked",
    conversationReadReceiptsDisable: 'Turn off read receipts',
    conversationReadReceiptsEnable: 'Turn on read receipts',
    readReceiptPopupTitle: 'Read by',
    cancel: 'Cancel',
    add: 'Add',
    save: 'Save',
    done: 'Done',
    delete: 'Delete',
    profileIconSection: 'Icons',
    profileBackgroundSection: 'Background images',
    profileNicknameHint: (_) =>
        "Friends see the nickname you've selected here instead of your Rhing ID.",
    profileAddNickname: (_) => 'Add a nickname',
    profileAddStatusMessage: (_) => 'Add a status message',
    profileNicknameDialogTitle: (_) => 'Add a nickname',
    profileNicknameDialogEditTitle: (_) => 'Edit nickname',
    profileNicknameDialogHint: (_) => 'Enter the name shown to friends',
    profileStatusMessageDialogTitle: (_) => 'Add a status message',
    profileStatusMessageDialogEditTitle: (_) => 'Edit status message',
    profileStatusMessageDialogHint: (_) => 'Enter a short status message',
    profileSnsLinkSectionTitle: 'SNS links',
    profileAddSnsLink: 'Add a URL',
    profileSnsLinkDialogTitle: 'Add a URL',
    profileSnsLinkDialogEditTitle: 'Edit URL',
    profileSnsLinkDialogHint: 'https://...',
    profileSnsLinkInvalidError: 'Please enter a valid URL',
    workshopSnsLinkFieldLabel: 'URL',
    profileSaveError: 'Failed to save',
    profileIconUploadError: 'Failed to upload icon',
    profileBackgroundUploadError: 'Failed to upload background image',
    workshopCardNameLabel: 'Card name (private label for you)',
    workshopCardDialogTitleNew: 'Create a profile card',
    workshopCardDialogTitleEdit: 'Edit profile card',
    workshopFieldIcon: 'Icon',
    workshopFieldBackground: 'Background image',
    workshopChoiceNone: 'None',
    workshopChoiceSelected: 'Selected',
    workshopChoiceSelect: 'Select',
    workshopEmptyMaterialHint: 'Nothing registered in your storehouse yet',
    fieldRequiredError: 'Please enter a value',
    enmusubiInviteLinkTitle: 'Invite link',
    enmusubiInviteLinkDescription:
        'Anyone who opens this link can send you a friend request.',
    enmusubiCopyLink: 'Copy',
    enmusubiQrTitle: 'Exchange via QR code',
    enmusubiQrDescription:
        'Scan a QR code in person to become friends quickly.',
    enmusubiScanButton: 'Scan a QR code',
    enmusubiScanScreenTitle: 'Scan a QR code',
    inviteScreenTitle: 'Friend request',
    inviteConfirmDescriptionTemplate: (rhingId) =>
        'Send a friend request to @$rhingId?',
    inviteScreenSendButton: 'Send friend request',
    inviteScreenGoHome: 'Back to home',
    inviteScreenInvalid: 'This link is invalid',
    groupMenuProfileCard: 'Profile card',
    groupMenuMemberList: 'Member list',
    groupMenuCreateInvite: 'Create invite link',
    groupMenuLeave: 'Leave',
    groupProfileCardNameLabel: 'Plaza name',
    groupProfileCardDescriptionLabel: 'Status',
    groupMemberListTitle: 'Members',
    groupMemberListPendingSection: 'Join requests',
    groupMemberListMembersSection: 'Members',
    groupRoleModerator: 'Moderator',
    groupRoleMember: 'Member',
    groupInviteDialogTitle: 'Invite link',
    groupInviteDialogDescription:
        'Anyone who opens this link can request to join this plaza, '
        'subject to approval by the owner or a moderator.',
    groupLeaveConfirmTitle: 'Leave this plaza?',
    groupLeaveConfirmMessage:
        "You won't be able to see this plaza's messages after leaving.",
    groupLeaveButton: 'Leave',
    groupLeaveOwnerError: 'The owner cannot leave',
    groupJoinScreenTitle: 'Join plaza',
    groupJoinInvalid: 'This invite link is invalid',
    groupJoinAlreadyMember: "You're already a member of this plaza",
    groupJoinPending:
        "You've already requested to join. Waiting for approval.",
    groupJoinDescriptionTemplate: (groupName) =>
        'Request to join "$groupName"? '
        'You can join once the owner or a moderator approves.',
    groupJoinRequestButton: 'Request to join',
    groupJoinRequestSent: 'Join request sent. Waiting for approval.',
    groupJoinOpenGroup: 'Open plaza',
    groupJoinRetry: 'Retry',
    groupJoinPendingListSubtitle: 'Request pending approval',
    groupJoinPendingDialogClose: 'Close',
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
