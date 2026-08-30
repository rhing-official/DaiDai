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
    required this.addMenuDmTitleTemplate,
    required this.addMenuDmSubtitle,
    required this.addMenuGroupTitleTemplate,
    required this.addMenuGroupSubtitle,
    required this.talksSearchHint,
    required this.talksSearchNoResults,
    required this.settingsFolderAccount,
    required this.settingsFolderApplication,
    required this.settingsFolderDesign,
    required this.settingsFolderLanguage,
    required this.settingsFolderNotifications,
    required this.settingsFolderTalk,
    required this.settingsFolderSupport,
    required this.settingsBlockedUsersTitle,
    required this.settingsBlockedUsersEmpty,
    required this.settingsBlockedUsersUnblock,
    required this.settingsAccentColor,
    required this.settingsAccentColorGekigaHint,
    required this.settingsAppearanceGekigaLockedHint,
    required this.settingsAppearance,
    required this.settingsAppearanceLight,
    required this.settingsAppearanceDark,
    required this.settingsAppearanceSystem,
    required this.settingsColorCode,
    required this.settingsColorPresets,
    required this.settingsCustomColors,
    required this.settingsCustomColorRegister,
    required this.settingsCustomColorLimitReachedTemplate,
    required this.settingsCustomColorDeleteConfirmTitle,
    required this.settingsCustomColorDeleteConfirmButton,
    required this.settingsLogout,
    required this.settingsDisplayLanguage,
    required this.settingsTimeFormat,
    required this.settingsTimeFormat24h,
    required this.settingsTimeFormat12h,
    required this.settingsSubUI,
    required this.settingsUIDescription,
    required this.settingsUiStyleFlatLabel,
    required this.settingsUiStyleFlatDescription,
    required this.settingsUiStyleGekigaLabel,
    required this.settingsUiStyleGekigaDescription,
    required this.settingsUiStyleGlassLabel,
    required this.settingsUiStyleGlassDescription,
    required this.settingsChatLayoutTitle,
    required this.settingsChatLayoutSideBySide,
    required this.settingsChatLayoutSideBySideDescription,
    required this.settingsChatLayoutAllLeft,
    required this.settingsChatLayoutAllLeftDescription,
    required this.settingsSubTypography,
    required this.settingsFontDesign,
    required this.settingsAccountInfoSection,
    required this.settingsRhingIdLabel,
    required this.settingsSecurity,
    required this.settingsPassword,
    required this.settingsTwoFactor,
    required this.twoFactorEnabledStatus,
    required this.twoFactorDisabledStatus,
    required this.twoFactorSetupDialogTitle,
    required this.twoFactorSetupDescription,
    required this.twoFactorSecretKeyLabel,
    required this.twoFactorCodeLabel,
    required this.twoFactorEnrollButton,
    required this.twoFactorInvalidCodeError,
    required this.twoFactorDisableConfirmTitle,
    required this.twoFactorDisableConfirmMessage,
    required this.twoFactorDisableConfirmButton,
    required this.twoFactorRequiresRecentLoginError,
    required this.twoFactorReauthenticateButton,
    required this.twoFactorChallengeTitle,
    required this.twoFactorChallengeDescription,
    required this.twoFactorChallengeConfirmButton,
    required this.qrLoginDialogTitle,
    required this.qrLoginDialogDescription,
    required this.qrLoginExpiredMessage,
    required this.qrLoginRefreshButton,
    required this.qrLoginSignInError,
    required this.qrLoginScanConfirmTitle,
    required this.qrLoginScanConfirmMessage,
    required this.qrLoginScanConfirmButton,
    required this.qrLoginInvalidQrError,
    required this.qrLoginApproveError,
    required this.qrLoginScanInstructionMessage,
    required this.qrLoginScanInstructionButton,
    required this.settingsPasskey,
    required this.settingsQrLogin,
    required this.settingsDeleteAccount,
    required this.settingsComingSoon,
    required this.settingsSendKeyTitle,
    required this.settingsSendKeyEnterToSend,
    required this.settingsSendKeyCtrlEnterToSend,
    required this.settingsSendKeySilentEnterToSend,
    required this.settingsSendKeySilentCtrlEnterToSend,
    required this.settingsAdvancedSectionTitle,
    required this.settingsStickerSendModeTitle,
    required this.settingsStickerSendModeLine,
    required this.settingsStickerSendModeLineSubtitle,
    required this.settingsStickerSendModeDiscord,
    required this.settingsStickerSendModeDiscordSubtitle,
    required this.settingsDraftSyncTitle,
    required this.settingsDraftSyncSubtitle,
    required this.back,
    required this.friendSearchTitle,
    required this.friendSearchHint,
    required this.friendSearchLabel,
    required this.friendSearchButton,
    required this.friendSearchSearchButton,
    required this.friendSearchNotFound,
    required this.friendSearchSelf,
    required this.friendRequestSent,
    required this.friendRequestAlreadySent,
    required this.friendRequestAlreadyFriends,
    required this.friendRequestAccept,
    required this.friendRequestDecline,
    required this.userProfileCardSendRequest,
    required this.userProfileCardAcceptRequest,
    required this.userProfileCardRequestPending,
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
    required this.conversationReadReceiptsDisableConfirmTitle,
    required this.conversationReadReceiptsDisableConfirmMessage,
    required this.conversationReadReceiptsDisableConfirmButton,
    required this.conversationReadReceiptsProposeDisable,
    required this.conversationReadReceiptsProposeEnable,
    required this.conversationReadReceiptsBannerWaitingOff,
    required this.conversationReadReceiptsBannerWaitingOn,
    required this.conversationReadReceiptsBannerProposedOff,
    required this.conversationReadReceiptsBannerProposedOn,
    required this.conversationReadReceiptsBannerAcceptButton,
    required this.conversationReadReceiptsBannerDeclineButton,
    required this.conversationReadReceiptsBannerCancelButton,
    required this.conversationProposeSeverance,
    required this.severanceProposeDialogTitle,
    required this.severanceProposeDialogMessage,
    required this.severanceProposeButton,
    required this.severanceAcceptDialogTitle,
    required this.severanceAcceptDialogMessage,
    required this.severanceAcceptButton,
    required this.severanceBannerWaitingForOther,
    required this.severanceBannerCancelButton,
    required this.severanceBannerProposedByOther,
    required this.severanceBannerDeclineButton,
    required this.severanceBannerAcceptButton,
    required this.readReceiptPopupTitle,
    required this.reactionListPopupTitle,
    required this.chatSelectionModeTitle,
    required this.chatDeleteConfirmTitle,
    required this.chatDeleteConfirmMessage,
    required this.chatDeleteConfirmButton,
    required this.chatReplyAction,
    required this.chatEditAction,
    required this.chatUnsendAction,
    required this.chatReactAction,
    required this.chatCopyAction,
    required this.chatPartialCopyAction,
    required this.chatSelectAction,
    required this.chatPinAction,
    required this.chatUnpinAction,
    required this.chatPinnedMessagesTooltip,
    required this.chatPinnedMessagesEmpty,
    required this.chatScreenshotAction,
    required this.chatScreenshotSelectionModeTitle,
    required this.chatScreenshotDialogTitle,
    required this.chatScreenshotBlurCheckboxLabel,
    required this.chatScreenshotConfirmButton,
    required this.chatScreenshotErrorMessage,
    required this.chatEditedLabel,
    required this.chatInputHint,
    required this.announcementContactFormLabel,
    required this.chatReplyingToLabel,
    required this.chatEditingLabel,
    required this.chatUnsendConfirmTitle,
    required this.chatUnsendConfirmMessage,
    required this.chatUnsendConfirmButton,
    required this.chatAttachFile,
    required this.chatAttachImage,
    required this.chatAttachVideo,
    required this.chatAttachCapture,
    required this.chatNoStickersMessage,
    required this.stickerPackNotFoundMessage,
    required this.stickerSearchHint,
    required this.settingsStickersSection,
    required this.settingsManageOwnedStickers,
    required this.ownedStickersScreenTitle,
    required this.uninstallStickerButton,
    required this.uninstallStickerConfirmTitle,
    required this.uninstallStickerConfirmMessage,
    required this.uninstallStickerConfirmButton,
    required this.chatAttachmentTooLargeMessage,
    required this.chatAttachmentBlockedExtensionMessage,
    required this.chatAttachmentSendFailedMessage,
    required this.chatResendAction,
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
    required this.groupMenuManageRoles,
    required this.groupMenuLeave,
    required this.groupRoleListEmpty,
    required this.groupRoleCreateDialogTitle,
    required this.groupRoleEditDialogTitle,
    required this.groupRoleDialogNameLabel,
    required this.groupRoleColorInvalid,
    required this.groupRoleColorNone,
    required this.groupRolePermissionsLabel,
    required this.groupPermissionLabel,
    required this.groupRoleEveryoneNote,
    required this.groupRoleDeleteConfirmTitle,
    required this.groupRoleDeleteConfirmButton,
    required this.groupRoleNoneLabel,
    required this.groupRolePickerTitle,
    required this.groupRoleMembersLabel,
    required this.groupRoleAssignAllLabel,
    required this.groupRolePriorityTitle,
    required this.groupRolePriorityHint,
    required this.groupRoomRolePriorityMenuItem,
    required this.groupRoomRolePriorityResetButton,
    required this.groupMenuEnableMultipleRooms,
    required this.dmMenuEnableMultipleRooms,
    required this.groupSettingsDefaultMuteLabel,
    required this.groupSettingsDefaultMuteHint,
    required this.groupSettingsDefaultReadReceiptsLabel,
    required this.groupSettingsDefaultReadReceiptsHint,
    required this.groupRoomCustomSettingsLabel,
    required this.groupRoomCustomSettingsHint,
    required this.groupSettingsDisableMultipleRoomsLabel,
    required this.groupSettingsDisableMultipleRoomsHint,
    required this.groupSettingsDisableMultipleRoomsBlockedHint,
    required this.groupSettingsDisableMultipleRoomsConfirmTitle,
    required this.groupSettingsDisableMultipleRoomsConfirmMessage,
    required this.groupSettingsDisableMultipleRoomsConfirmButton,
    required this.profileCardPickerLabel,
    required this.profileCardPickerStandardOption,
    required this.profileCardPickerStandardOptionWithName,
    required this.settingsProfileCardAssignmentTitle,
    required this.settingsProfileCardAssignmentHint,
    required this.settingsProfileCardAssignmentEmpty,
    required this.conversationProfileCardMenuLabel,
    required this.workshopConversationCardAddDialogTitle,
    required this.workshopConversationCardAddEmpty,
    required this.workshopConversationCardSearchHint,
    required this.groupSettingsTooltip,
    required this.groupTransferOwnershipMenuItem,
    required this.groupTransferOwnershipConfirmTitle,
    required this.groupTransferOwnershipConfirmMessage,
    required this.groupTransferOwnershipConfirmButton,
    required this.groupProfileCardNameLabel,
    required this.groupProfileCardDescriptionLabel,
    required this.groupMemberListTitle,
    required this.groupMemberListPendingSection,
    required this.groupMemberListMembersSection,
    required this.groupInviteDialogTitle,
    required this.groupInviteDialogDescription,
    required this.groupLeaveConfirmTitle,
    required this.groupLeaveConfirmMessage,
    required this.groupLeaveButton,
    required this.groupLeaveOwnerError,
    required this.groupDeleteMenuLabel,
    required this.groupDeleteConfirmTitle,
    required this.groupDeleteConfirmMessage,
    required this.groupDeleteButton,
    required this.groupJoinScreenTitle,
    required this.groupJoinInvalid,
    required this.groupJoinAlreadyMember,
    required this.groupJoinPending,
    required this.groupJoinDescriptionTemplate,
    required this.groupJoinRequestButton,
    required this.groupJoinRequestSent,
    required this.groupJoinOpenGroup,
    required this.groupJoinRetry,
    required this.settingsDeleteAccountConfirmTitle,
    required this.settingsDeleteAccountGraceOption,
    required this.settingsDeleteAccountGraceOptionSubtitle,
    required this.settingsDeleteAccountImmediate,
    required this.settingsDeleteAccountImmediateOptionSubtitle,
    required this.settingsDeleteAccountCancelButton,
    required this.accountDeleteOwnerGuardTitle,
    required this.accountDeleteOwnerGuardMessage,
    required this.accountDeleteOwnerGuardCleared,
    required this.accountDeleteOwnerGuardContinue,
    required this.accountRestoreTitle,
    required this.accountRestoreMessage,
    required this.accountRestoreButton,
    required this.accountRestoreSignOutButton,
    required this.accountSuspendedTitle,
    required this.accountSuspendedMessage,
    required this.accountSuspendedSignOutButton,
    required this.chatAccountDeletedNotice,
    required this.chatAccountDeletedDeleteConversationPrompt,
    required this.chatAccountDeletedYesButton,
    required this.chatAccountDeletedNoButton,
    required this.chatAccountDeletedConfirmTitle,
    required this.chatAccountDeletedConfirmButton,
    required this.chatNoMoreHistory,
    required this.roomListAddDialogTitle,
    required this.roomListAddButton,
    required this.roomListDeleteConfirmTitle,
    required this.roomListDeleteConfirmButton,
    required this.roomRenameLabel,
    required this.roomMenuDeleteLabel,
    required this.roomDeleteLastRoomError,
    required this.dmMenuDeleteConversation,
    required this.chatAddToAlbumAction,
    required this.albumButtonTooltip,
    required this.albumListTitle,
    required this.albumListEmptyMessage,
    required this.albumCreateButtonLabel,
    required this.albumCreateDialogTitle,
    required this.albumNameFieldHint,
    required this.albumRenameAction,
    required this.albumRenameDialogTitle,
    required this.albumDeleteAction,
    required this.albumDeleteConfirmTitle,
    required this.albumDeleteConfirmMessage,
    required this.albumItemCountLabel,
    required this.albumRemoveItemAction,
    required this.albumRemoveItemConfirmTitle,
    required this.albumRemoveItemConfirmMessage,
    required this.albumPickerTitle,
    required this.albumPickerCreateNewOption,
    required this.albumAddedSnackbarMessage,
    required this.albumAddFailedSnackbarMessage,
    required this.commonCreate,
  });

  final String navTalk;
  final String navProfile;
  final String navSettings;

  /// 一対/DM等の用語を差し込んだタイトルを組み立てる（例: 「一対を始める」）。
  final String Function(String dmTerm) addMenuDmTitleTemplate;
  final String addMenuDmSubtitle;

  /// 広場/Server等の用語を差し込んだタイトルを組み立てる（例: 「広場を作る」）。
  final String Function(String plazaTerm) addMenuGroupTitleTemplate;
  final String addMenuGroupSubtitle;
  final String talksSearchHint;
  final String talksSearchNoResults;

  final String settingsFolderAccount;
  final String settingsFolderApplication;
  final String settingsFolderDesign;
  final String settingsFolderLanguage;
  final String settingsFolderNotifications;
  final String settingsFolderTalk;
  final String settingsFolderSupport;
  final String settingsBlockedUsersTitle;
  final String settingsBlockedUsersEmpty;
  final String settingsBlockedUsersUnblock;
  final String settingsAccentColor;
  final String settingsAccentColorGekigaHint;
  final String settingsAppearanceGekigaLockedHint;
  final String settingsAppearance;
  final String settingsAppearanceLight;
  final String settingsAppearanceDark;
  final String settingsAppearanceSystem;
  final String settingsColorCode;
  final String settingsColorPresets;
  final String settingsCustomColors;
  final String settingsCustomColorRegister;
  final String Function(int max) settingsCustomColorLimitReachedTemplate;
  final String settingsCustomColorDeleteConfirmTitle;
  final String settingsCustomColorDeleteConfirmButton;
  final String settingsLogout;
  final String settingsDisplayLanguage;
  final String settingsTimeFormat;
  final String settingsTimeFormat24h;
  final String settingsTimeFormat12h;
  final String settingsSubUI;
  final String settingsUIDescription;

  /// UIスタイル選択肢（2026-07-29追加、2026-08-12改名: シンプル→フラット）。
  /// 「フラット」は現行の標準見た目、「劇画」は手描き風・ギザギザした
  /// 太い黒線・モノクロの吹き出しのメッセージ画面用スタイル
  /// （現時点ではメッセージ画面のみ対応）。
  final String settingsUiStyleFlatLabel;
  final String settingsUiStyleFlatDescription;
  final String settingsUiStyleGekigaLabel;
  final String settingsUiStyleGekigaDescription;
  final String settingsUiStyleGlassLabel;
  final String settingsUiStyleGlassDescription;

  /// 「メッセージの表示」（2026-07-30改名、旧称: 語らいの表示）。旧「入力」
  /// カテゴリ廃止に伴い、語らいカテゴリへ移動した（settings_tab.dart参照）。
  final String settingsChatLayoutTitle;
  final String settingsChatLayoutSideBySide;
  final String settingsChatLayoutSideBySideDescription;
  final String settingsChatLayoutAllLeft;
  final String settingsChatLayoutAllLeftDescription;
  final String settingsSubTypography;
  final String settingsFontDesign;
  final String settingsAccountInfoSection;
  final String settingsRhingIdLabel;
  final String settingsSecurity;
  final String settingsPassword;
  final String settingsTwoFactor;
  final String twoFactorEnabledStatus;
  final String twoFactorDisabledStatus;
  final String twoFactorSetupDialogTitle;
  final String twoFactorSetupDescription;
  final String twoFactorSecretKeyLabel;
  final String twoFactorCodeLabel;
  final String twoFactorEnrollButton;
  final String twoFactorInvalidCodeError;
  final String twoFactorDisableConfirmTitle;
  final String twoFactorDisableConfirmMessage;
  final String twoFactorDisableConfirmButton;
  final String twoFactorRequiresRecentLoginError;
  final String twoFactorReauthenticateButton;
  final String twoFactorChallengeTitle;
  final String twoFactorChallengeDescription;
  final String twoFactorChallengeConfirmButton;
  final String qrLoginDialogTitle;
  final String qrLoginDialogDescription;
  final String qrLoginExpiredMessage;
  final String qrLoginRefreshButton;
  final String qrLoginSignInError;
  final String qrLoginScanConfirmTitle;
  final String qrLoginScanConfirmMessage;
  final String qrLoginScanConfirmButton;
  final String qrLoginInvalidQrError;
  final String qrLoginApproveError;
  final String qrLoginScanInstructionMessage;
  final String qrLoginScanInstructionButton;
  final String settingsPasskey;
  final String settingsQrLogin;
  final String settingsDeleteAccount;
  final String settingsComingSoon;
  final String settingsSendKeyTitle;
  final String settingsSendKeyEnterToSend;
  final String settingsSendKeyCtrlEnterToSend;
  final String settingsSendKeySilentEnterToSend;
  final String settingsSendKeySilentCtrlEnterToSend;
  final String settingsAdvancedSectionTitle;
  final String settingsStickerSendModeTitle;
  final String settingsStickerSendModeLine;
  final String settingsStickerSendModeLineSubtitle;
  final String settingsStickerSendModeDiscord;
  final String settingsStickerSendModeDiscordSubtitle;
  final String settingsDraftSyncTitle;
  final String settingsDraftSyncSubtitle;

  final String back;

  final String friendSearchTitle;
  final String friendSearchHint;
  final String friendSearchLabel;
  final String friendSearchButton;

  /// Rhing ID検索フォームの最初の一歩（検索）ボタン。相手が見つかったら
  /// カード選択を含む確認UIに切り替わり、[friendSearchButton]が送信ボタンに
  /// なる（2026-07-29追加）。
  final String friendSearchSearchButton;
  final String friendSearchNotFound;
  final String friendSearchSelf;
  final String friendRequestSent;
  final String friendRequestAlreadySent;
  final String friendRequestAlreadyFriends;
  final String friendRequestAccept;
  final String friendRequestDecline;
  final String userProfileCardSendRequest;
  final String userProfileCardAcceptRequest;
  final String userProfileCardRequestPending;
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
  final String conversationReadReceiptsDisableConfirmTitle;
  final String conversationReadReceiptsDisableConfirmMessage;
  final String conversationReadReceiptsDisableConfirmButton;
  final String conversationReadReceiptsProposeDisable;
  final String conversationReadReceiptsProposeEnable;
  final String conversationReadReceiptsBannerWaitingOff;
  final String conversationReadReceiptsBannerWaitingOn;
  final String Function(String senderLabel)
  conversationReadReceiptsBannerProposedOff;
  final String Function(String senderLabel)
  conversationReadReceiptsBannerProposedOn;
  final String conversationReadReceiptsBannerAcceptButton;
  final String conversationReadReceiptsBannerDeclineButton;
  final String conversationReadReceiptsBannerCancelButton;
  final String conversationProposeSeverance;
  final String severanceProposeDialogTitle;
  final String severanceProposeDialogMessage;
  final String severanceProposeButton;
  final String severanceAcceptDialogTitle;
  final String severanceAcceptDialogMessage;
  final String severanceAcceptButton;
  final String severanceBannerWaitingForOther;
  final String severanceBannerCancelButton;
  final String severanceBannerProposedByOther;
  final String severanceBannerDeclineButton;
  final String severanceBannerAcceptButton;
  final String readReceiptPopupTitle;
  final String reactionListPopupTitle;
  final String Function(int count) chatSelectionModeTitle;
  final String chatDeleteConfirmTitle;
  final String chatDeleteConfirmMessage;
  final String chatDeleteConfirmButton;
  final String chatReplyAction;
  final String chatEditAction;
  final String chatUnsendAction;
  final String chatReactAction;
  final String chatCopyAction;
  final String chatPartialCopyAction;
  final String chatSelectAction;
  final String chatPinAction;
  final String chatUnpinAction;
  final String chatPinnedMessagesTooltip;
  final String chatPinnedMessagesEmpty;
  final String chatScreenshotAction;
  final String Function(int count) chatScreenshotSelectionModeTitle;
  final String chatScreenshotDialogTitle;
  final String chatScreenshotBlurCheckboxLabel;
  final String chatScreenshotConfirmButton;
  final String chatScreenshotErrorMessage;
  final String chatEditedLabel;
  final String chatInputHint;
  final String announcementContactFormLabel;
  final String Function(String senderLabel) chatReplyingToLabel;
  final String chatEditingLabel;
  final String chatUnsendConfirmTitle;
  final String chatUnsendConfirmMessage;
  final String chatUnsendConfirmButton;
  final String chatAttachFile;
  final String chatAttachImage;
  final String chatAttachVideo;
  final String chatAttachCapture;
  final String chatNoStickersMessage;
  final String stickerPackNotFoundMessage;
  final String stickerSearchHint;
  final String settingsStickersSection;
  final String settingsManageOwnedStickers;
  final String ownedStickersScreenTitle;
  final String uninstallStickerButton;
  final String uninstallStickerConfirmTitle;
  final String uninstallStickerConfirmMessage;
  final String uninstallStickerConfirmButton;
  final String chatAttachmentTooLargeMessage;
  final String chatAttachmentBlockedExtensionMessage;
  final String chatAttachmentSendFailedMessage;
  final String chatResendAction;

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
  final String groupMenuManageRoles;
  final String groupMenuLeave;

  final String groupRoleListEmpty;
  final String groupRoleCreateDialogTitle;
  final String groupRoleEditDialogTitle;
  final String groupRoleDialogNameLabel;
  final String groupRoleColorInvalid;

  /// 色のhex入力欄の横に置く「色を設定しない」チェックボックス。
  final String groupRoleColorNone;

  /// ロール編集ダイアログの権限チェックボックス群のセクション見出し。
  final String groupRolePermissionsLabel;

  /// 権限1件分の表示ラベル（[GroupPermission]の定数を渡す）。
  final String Function(String permission) groupPermissionLabel;

  /// 基準ロール（全員に自動適用、削除・名前変更不可）の編集ダイアログに出す注記。
  final String groupRoleEveryoneNote;
  final String groupRoleDeleteConfirmTitle;
  final String groupRoleDeleteConfirmButton;
  final String groupRoleNoneLabel;
  final String groupRolePickerTitle;

  /// ロール編集ダイアログ内、そのロールを付与するメンバーを選ぶセクションの見出し。
  final String groupRoleMembersLabel;

  /// メンバー選択セクションの「全員に付与」一括選択チェックボックス。
  final String groupRoleAssignAllLabel;

  /// ロールの優先順位（呼び名の色を決める順序）並べ替え画面のタイトル。
  final String groupRolePriorityTitle;
  final String groupRolePriorityHint;

  /// 寄合ハンバーガーメニューの「この寄合の色優先順位を設定」項目。
  final String groupRoomRolePriorityMenuItem;

  /// 寄合ごとの優先順位上書きを解除し、広場全体の設定に戻すボタン。
  final String groupRoomRolePriorityResetButton;

  /// 広場のハンバーガーメニュー、単一モードから複数モードへの切り替え項目
  /// （`Group.roomsEnabled`、2026-07-29追加）。
  final String groupMenuEnableMultipleRooms;

  /// 一対のハンバーガーメニュー、単一モードから複数モードへの切り替え項目
  /// （`DirectMessage.roomsEnabled`、2026-07-29追加）。
  final String dmMenuEnableMultipleRooms;

  /// 広場全体設定ポップアップの、通知オフのデフォルト値トグル
  /// （2026-07-29追加、寄合ごとに「この寄合独自の設定」で上書き可能）。
  final String groupSettingsDefaultMuteLabel;
  final String groupSettingsDefaultMuteHint;

  /// 広場全体設定ポップアップの、既読機能オン/オフのデフォルト値トグル。
  final String groupSettingsDefaultReadReceiptsLabel;
  final String groupSettingsDefaultReadReceiptsHint;

  /// 寄合ハンバーガーメニュー最下部の「この寄合独自の設定」トグル。ONの間、
  /// 通知・既読・ロールの優先順位を広場全体の設定より優先してこの寄合だけ
  /// 個別に設定できる（`Room.customSettingsEnabled`、2026-07-29追加）。
  final String groupRoomCustomSettingsLabel;
  final String groupRoomCustomSettingsHint;

  /// 全体設定の「寄合を単一にまとめる」項目。寄合が1つだけの場合のみ
  /// 有効化できる（2026-07-29追加）。
  final String groupSettingsDisableMultipleRoomsLabel;
  final String groupSettingsDisableMultipleRoomsHint;

  /// 寄合が複数あって無効化できない場合の説明文言。
  final String groupSettingsDisableMultipleRoomsBlockedHint;
  final String groupSettingsDisableMultipleRoomsConfirmTitle;
  final String groupSettingsDisableMultipleRoomsConfirmMessage;
  final String groupSettingsDisableMultipleRoomsConfirmButton;

  /// 会話（一対・広場）ごとに使うプロフィールカードを選ぶピッカーのラベル
  /// （`AppUser.conversationProfileCardId`、2026-07-29追加）。広場参加・
  /// 友達申請3系統・全体設定の計5箇所で共通して使う。
  final String profileCardPickerLabel;

  /// [profileCardPickerLabel]のピッカーで「標準（[AppUser.activeProfileCardId]）
  /// を使う」ことを表す選択肢のラベル。
  final String profileCardPickerStandardOption;

  /// [profileCardPickerStandardOption]の、現在の標準カードの名前が分かって
  /// いる場合の表示（例:「標準（いい）」）。標準として選べるカードと、同名の
  /// カードそのものを選ぶ選択肢が並んで見え、重複しているように見える指摘を
  /// 受けて追加（2026-08-05）。「標準」自体（今後デフォルトを変えれば自動で
  /// 追従する）と「そのカードに固定」という意味の違いは変えず、表示だけ
  /// 現在の解決結果を分かりやすくする。
  final String Function(String cardName)
  profileCardPickerStandardOptionWithName;

  /// 身だしなみ＞工房内、会話ごとのプロフィールカード割り当て一覧セクションの
  /// タイトル（2026-07-29追加、2026-08-02に設定＞語らいから工房へ移動）。
  final String settingsProfileCardAssignmentTitle;

  /// 上記セクションのタイトル直下に添える一言説明。「相手のカードを選ぶ」
  /// 機能だと誤解されやすいため、自分が使うカードを選ぶ機能であることを
  /// 明示する（2026-07-30追加）。工房移動後は「標準カード以外を使う語らいだけ
  /// 表示する」絞り込みの説明も兼ねる（2026-08-02更新）。
  final String settingsProfileCardAssignmentHint;

  /// 上記セクションで、標準以外のカードを使っている語らいが1件も無い場合に
  /// 表示する文言（2026-08-02更新、絞り込み後の空状態）。
  final String settingsProfileCardAssignmentEmpty;

  /// 各会話（一対のハンバーガーメニュー・広場の全体設定）から直接開く、
  /// その会話で自分が使うプロフィールカードを選ぶメニュー項目・ダイアログ
  /// タイトルの両方に使う（2026-07-30追加、`ConversationProfileCardDialog`）。
  final String conversationProfileCardMenuLabel;

  /// 工房の会話ごとのプロフィールカードセクションにある＋ボタンで開く、
  /// 対象の語らいを選ぶダイアログのタイトル。
  final String workshopConversationCardAddDialogTitle;

  /// 上記ダイアログで、選べる語らい（まだ標準カードのままの語らい）が
  /// 1件も無い場合に表示するメッセージ（SnackBar）。
  final String workshopConversationCardAddEmpty;

  /// 上記ダイアログ内の、名前で絞り込む検索ボックスのヒント文言。
  final String workshopConversationCardSearchHint;

  /// サイドバーの「広場自体の設定」アイコンのツールチップ。
  final String groupSettingsTooltip;

  /// 長の譲渡メニュー項目・確認ダイアログ。
  final String groupTransferOwnershipMenuItem;
  final String groupTransferOwnershipConfirmTitle;
  final String groupTransferOwnershipConfirmMessage;
  final String groupTransferOwnershipConfirmButton;

  final String groupProfileCardNameLabel;
  final String groupProfileCardDescriptionLabel;

  final String groupMemberListTitle;
  final String groupMemberListPendingSection;
  final String groupMemberListMembersSection;

  final String groupInviteDialogTitle;
  final String groupInviteDialogDescription;

  final String groupLeaveConfirmTitle;
  final String groupLeaveConfirmMessage;
  final String groupLeaveButton;
  final String groupLeaveOwnerError;

  /// 広場を丸ごと削除する機能（2026-08-02追加、長のみ）のメニュー項目
  /// ラベル。複数モードの全体設定（`GroupSettingsPopup`）・単一モードの
  /// ハンバーガーメニューの両方で使う。
  final String groupDeleteMenuLabel;
  final String groupDeleteConfirmTitle;
  final String groupDeleteConfirmMessage;
  final String groupDeleteButton;

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

  /// アカウント削除の選択ポップアップのタイトル。
  final String settingsDeleteAccountConfirmTitle;

  /// 30日間の復元猶予期間を経る通常削除の選択肢カードのタイトル。
  final String settingsDeleteAccountGraceOption;
  final String settingsDeleteAccountGraceOptionSubtitle;

  /// 30日間の復元猶予期間を経ない、即時削除（復元不可）の選択肢カードの
  /// タイトル（操作行ラベルにも流用）。
  final String settingsDeleteAccountImmediate;
  final String settingsDeleteAccountImmediateOptionSubtitle;

  /// アカウント削除の選択ポップアップの「やめる」ボタン。
  final String settingsDeleteAccountCancelButton;

  /// 長を務める広場が残っている間、アカウント削除（通常・即時どちらも）を
  /// 先に進ませないためのガードダイアログの文言（2026-08-02追加）。
  final String accountDeleteOwnerGuardTitle;

  /// 対象の広場が1件以上ある場合に表示する説明文。
  final String accountDeleteOwnerGuardMessage;

  /// 全ての広場を譲渡し終えた（対象0件になった）場合に表示する文言。
  final String accountDeleteOwnerGuardCleared;

  /// 対象0件の時だけ押せる「続ける」ボタンのラベル。
  final String accountDeleteOwnerGuardContinue;

  final String accountRestoreTitle;

  /// 復元プロンプトの説明文。残り日数を差し込む。
  final String Function(int remainingDays) accountRestoreMessage;
  final String accountRestoreButton;
  final String accountRestoreSignOutButton;

  /// アカウント停止中（[AccountStatus.suspended]）に表示する画面の文言
  /// （2026-08-12追加）。管理者による停止のため、[AccountRestoreScreen]と
  /// 違い自己解除の手段は用意しない。
  final String accountSuspendedTitle;
  final String accountSuspendedMessage;
  final String accountSuspendedSignOutButton;

  /// アカウント削除通知メッセージの文言。相手のRhing IDを差し込む。
  final String Function(String label) chatAccountDeletedNotice;
  final String chatAccountDeletedDeleteConversationPrompt;
  final String chatAccountDeletedYesButton;
  final String chatAccountDeletedNoButton;
  final String chatAccountDeletedConfirmTitle;
  final String chatAccountDeletedConfirmButton;

  /// メッセージ一覧を一番上まで遡り、これ以上古い履歴が無い場合に表示する
  /// 終端表示（2026-08-20追加、1日単位ページネーション）。
  final String chatNoMoreHistory;

  /// 寄合追加ダイアログのタイトル。用語（「寄合」等）を差し込む。
  final String Function(String term) roomListAddDialogTitle;
  final String roomListAddButton;

  /// 寄合削除の確認ダイアログのタイトル。用語（「寄合」等）を差し込む。
  final String Function(String term) roomListDeleteConfirmTitle;
  final String roomListDeleteConfirmButton;

  /// 寄合の名前変更メニュー項目・ダイアログタイトルの両方に使う。
  final String Function(String term) roomRenameLabel;

  /// ハンバーガーメニューの「寄合を削除」項目（2026-07-30追加、寄合一覧の
  /// ごみ箱アイコンの代わり）。用語（「寄合」等）を差し込む。
  final String Function(String term) roomMenuDeleteLabel;

  /// 最後の1つの寄合を削除しようとした時のエラー表示（SnackBar）。
  final String roomDeleteLastRoomError;

  /// 一対のハンバーガーメニューの「削除」項目。相手がアカウントを削除した
  /// 通知に「いいえ」と答えた後（または未応答のまま）でも、いつでもここから
  /// 削除できる。用語（「一対」等）を差し込む。
  final String Function(String term) dmMenuDeleteConversation;

  // 寄合単位の共有アルバム機能（2026-08-30追加）。
  final String chatAddToAlbumAction;
  final String albumButtonTooltip;
  final String albumListTitle;
  final String albumListEmptyMessage;
  final String albumCreateButtonLabel;
  final String albumCreateDialogTitle;
  final String albumNameFieldHint;
  final String albumRenameAction;
  final String albumRenameDialogTitle;
  final String albumDeleteAction;
  final String albumDeleteConfirmTitle;
  final String albumDeleteConfirmMessage;
  final String Function(int count) albumItemCountLabel;
  final String albumRemoveItemAction;
  final String albumRemoveItemConfirmTitle;
  final String albumRemoveItemConfirmMessage;
  final String albumPickerTitle;
  final String albumPickerCreateNewOption;
  final String albumAddedSnackbarMessage;
  final String albumAddFailedSnackbarMessage;
  final String commonCreate;

  static final ja = Strings._(
    navTalk: '語らい',
    navProfile: '身だしなみ',
    navSettings: '設定',
    addMenuDmTitleTemplate: (dmTerm) => '$dmTermを始める',
    addMenuDmSubtitle: '1対1で話す相手を追加する',
    addMenuGroupTitleTemplate: (plazaTerm) => '$plazaTermを作る',
    addMenuGroupSubtitle: '3人以上のグループを作る',
    talksSearchHint: '語らいを検索',
    talksSearchNoResults: '見つかりませんでした',
    settingsFolderAccount: 'アカウント',
    settingsFolderApplication: 'アプリケーション',
    settingsFolderDesign: '色',
    settingsFolderLanguage: '言語',
    settingsFolderNotifications: '通知',
    settingsFolderTalk: '語らい',
    settingsFolderSupport: '運営',
    settingsBlockedUsersTitle: 'ブロックしたユーザー',
    settingsBlockedUsersEmpty: 'ブロックしたユーザーはいません',
    settingsBlockedUsersUnblock: 'ブロック解除',
    settingsAccentColor: 'アクセントカラー',
    settingsAccentColorGekigaHint: '劇画UIでは背景色として使われます',
    settingsAppearanceGekigaLockedHint: '劇画UIを選択中は変更できません',
    settingsAppearance: '外観',
    settingsAppearanceLight: 'ライト',
    settingsAppearanceDark: 'ダーク',
    settingsAppearanceSystem: '端末に合わせる',
    settingsColorCode: 'カラーコード',
    settingsColorPresets: 'プリセット',
    settingsCustomColors: '登録した色',
    settingsCustomColorRegister: 'この色を登録',
    settingsCustomColorLimitReachedTemplate: (max) => '登録上限（$max色）に達しています',
    settingsCustomColorDeleteConfirmTitle: 'この色を削除しますか？',
    settingsCustomColorDeleteConfirmButton: '削除する',
    settingsLogout: 'ログアウト',
    settingsDisplayLanguage: '表示言語',
    settingsTimeFormat: 'メッセージの時刻表示',
    settingsTimeFormat24h: '24時間表記',
    settingsTimeFormat12h: '12時間表記',
    settingsSubUI: 'UI',
    settingsUIDescription: 'アプリ全体の見た目を選べます。',
    settingsUiStyleFlatLabel: 'フラット',
    settingsUiStyleFlatDescription: 'デフォルトスタイル',
    settingsUiStyleGekigaLabel: '劇画',
    settingsUiStyleGekigaDescription: '奇抜な背景スタイル',
    settingsUiStyleGlassLabel: 'ガラス',
    settingsUiStyleGlassDescription: '半透明・縁が光るスタイル',
    settingsChatLayoutTitle: 'メッセージの表示',
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
    settingsAccountInfoSection: 'アカウント情報',
    settingsRhingIdLabel: 'Rhing ID',
    settingsSecurity: 'セキュリティ',
    settingsPassword: 'パスワード',
    settingsTwoFactor: '2段階認証',
    twoFactorEnabledStatus: '有効',
    twoFactorDisabledStatus: '無効',
    twoFactorSetupDialogTitle: '2段階認証を設定',
    twoFactorSetupDescription:
        '認証アプリ（Google Authenticator等）でQRコードを読み取るか、シークレットキーを手入力してから、表示された6桁のコードを入力してください。',
    twoFactorSecretKeyLabel: 'シークレットキー',
    twoFactorCodeLabel: '6桁のコード',
    twoFactorEnrollButton: '有効にする',
    twoFactorInvalidCodeError: 'コードが正しくありません',
    twoFactorDisableConfirmTitle: '2段階認証を無効にしますか？',
    twoFactorDisableConfirmMessage: '次回以降のログインでコードの入力を求められなくなります。',
    twoFactorDisableConfirmButton: '無効にする',
    twoFactorRequiresRecentLoginError: '確認のため、もう一度ログインしてからお試しください。',
    twoFactorReauthenticateButton: '再ログインする',
    twoFactorChallengeTitle: '認証アプリのコードを入力',
    twoFactorChallengeDescription: '認証アプリに表示されている6桁のコードを入力してください。',
    twoFactorChallengeConfirmButton: '確認',
    qrLoginDialogTitle: 'QRコードでログイン',
    qrLoginDialogDescription:
        'ログイン済みの端末でDaiDaiを開き、設定＞アカウント＞セキュリティ＞QRコードによるログインからこのQRコードを読み取ってください。',
    qrLoginExpiredMessage: 'QRコードの有効期限が切れました',
    qrLoginRefreshButton: '更新する',
    qrLoginSignInError: 'ログインに失敗しました',
    qrLoginScanConfirmTitle: 'この端末でのログインを許可しますか？',
    qrLoginScanConfirmMessage: '心当たりが無い場合は許可しないでください。',
    qrLoginScanConfirmButton: '許可する',
    qrLoginInvalidQrError: '無効なQRコードです',
    qrLoginApproveError: '承認に失敗しました。QRコードの有効期限が切れている可能性があります。',
    qrLoginScanInstructionMessage:
        '別の端末のサインイン画面で「QRコードでログイン」を開き、表示されたQRコードをこの端末で読み取ります。',
    qrLoginScanInstructionButton: 'スキャンを開始する',
    settingsPasskey: 'パスキー',
    settingsQrLogin: 'QRコードによるログイン',
    settingsDeleteAccount: 'アカウントを削除',
    settingsComingSoon: '準備中',
    settingsSendKeyTitle: 'メッセージの送信キー',
    settingsSendKeyEnterToSend: 'Enterで送信、Shift+Enterで改行',
    settingsSendKeyCtrlEnterToSend: 'Enterで改行、Ctrl+Enterで送信',
    settingsSendKeySilentEnterToSend: 'Ctrl+Enterで相手に通知せず送信',
    settingsSendKeySilentCtrlEnterToSend: 'Ctrl+Shift+Enterで相手に通知せず送信',
    settingsAdvancedSectionTitle: '詳細設定',
    settingsStickerSendModeTitle: 'ペタピタの送信方式',
    settingsStickerSendModeLine: '2回タップで送信',
    settingsStickerSendModeLineSubtitle: '1回目のタップで拡大表示、同じペタピタをもう一度タップすると送信します',
    settingsStickerSendModeDiscord: '1回タップで送信',
    settingsStickerSendModeDiscordSubtitle: 'タップすると即座に送信します',
    settingsDraftSyncTitle: '入力中のメッセージを他の端末と同期',
    settingsDraftSyncSubtitle: '入力欄に途中まで書いた内容を、別の端末で同じ語らいを開いたときに復元します',
    back: '戻る',
    friendSearchTitle: '友達を追加',
    friendSearchHint: '相手のRhing IDを入力して友達申請を送ります。承認されると会話できるようになります。',
    friendSearchLabel: '相手のRhing ID',
    friendSearchButton: '申請を送る',
    friendSearchSearchButton: '検索',
    friendSearchNotFound: 'そのRhing IDの住人は見つかりませんでした',
    friendSearchSelf: '自分自身には申請できません',
    friendRequestSent: '友達申請を送りました',
    friendRequestAlreadySent: 'すでに申請中です',
    friendRequestAlreadyFriends: 'すでに友達です',
    friendRequestAccept: '承認',
    friendRequestDecline: '拒否',
    userProfileCardSendRequest: '友達申請を送る',
    userProfileCardAcceptRequest: '友達申請を承認する',
    userProfileCardRequestPending: '申請中です。相手の承認をお待ちください',
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
    conversationReadReceiptsDisableConfirmTitle: '既読機能をオフにしますか？',
    conversationReadReceiptsDisableConfirmMessage: 'オフにすると今までの既読履歴が全て消えます。',
    conversationReadReceiptsDisableConfirmButton: 'オフにする',
    conversationReadReceiptsProposeDisable: '既読オフを提案する',
    conversationReadReceiptsProposeEnable: '既読オンを提案する',
    conversationReadReceiptsBannerWaitingOff: '既読機能オフの提案の承認待ちです',
    conversationReadReceiptsBannerWaitingOn: '既読機能オンの提案の承認待ちです',
    conversationReadReceiptsBannerProposedOff: (senderLabel) =>
        '$senderLabelによって既読機能オフに関する操作が行われました。許可しますか？',
    conversationReadReceiptsBannerProposedOn: (senderLabel) =>
        '$senderLabelによって既読機能オンに関する操作が行われました。許可しますか？',
    conversationReadReceiptsBannerAcceptButton: '許可する',
    conversationReadReceiptsBannerDeclineButton: '許可しない',
    conversationReadReceiptsBannerCancelButton: '取り消す',
    conversationProposeSeverance: '絶縁を提案',
    severanceProposeDialogTitle: '絶縁を提案しますか？',
    severanceProposeDialogMessage:
        '相手が同意すると、これまでの会話履歴が完全に削除され、友達関係も解消されます。相手が同意するまでは何も起こりません。',
    severanceProposeButton: '提案する',
    severanceAcceptDialogTitle: '絶縁に同意しますか？',
    severanceAcceptDialogMessage:
        '同意すると、これまでの会話履歴が完全に削除され、友達関係も解消されます。この操作は取り消せません。',
    severanceAcceptButton: '同意して削除する',
    severanceBannerWaitingForOther: '絶縁を提案しました。相手の同意をお待ちください',
    severanceBannerCancelButton: '取り消す',
    severanceBannerProposedByOther: '相手が絶縁を提案しています',
    severanceBannerDeclineButton: '今は同意しない',
    severanceBannerAcceptButton: '同意する',
    readReceiptPopupTitle: '既読',
    reactionListPopupTitle: 'リアクション',
    chatSelectionModeTitle: (count) => '$count件選択中',
    chatDeleteConfirmTitle: 'メッセージを削除しますか？',
    chatDeleteConfirmMessage:
        '選択したメッセージがあなたのアカウントから見えなくなります（相手には引き続き見えます）。全員が同じメッセージを削除すると、サーバーからも完全に削除されます。この操作は取り消せません。',
    chatDeleteConfirmButton: '削除',
    chatReplyAction: '返信',
    chatEditAction: '編集',
    chatUnsendAction: '送信取り消し',
    chatReactAction: 'リアクション',
    chatCopyAction: 'コピー',
    chatPartialCopyAction: '部分コピー',
    chatSelectAction: 'メッセージを削除',
    chatPinAction: 'ピン留め',
    chatUnpinAction: 'ピン留め解除',
    chatPinnedMessagesTooltip: 'ピン留めされたメッセージ',
    chatPinnedMessagesEmpty: 'ピン留めされたメッセージはありません',
    chatScreenshotAction: 'スクリーンショット',
    chatScreenshotSelectionModeTitle: (count) => '$count件を撮影',
    chatScreenshotDialogTitle: 'スクリーンショットを撮影',
    chatScreenshotBlurCheckboxLabel: '呼び名にぼかしを入れる',
    chatScreenshotConfirmButton: '撮影する',
    chatScreenshotErrorMessage: 'スクリーンショットの作成に失敗しました',
    chatEditedLabel: '編集済み',
    chatInputHint: 'メッセージを入力...',
    announcementContactFormLabel: '質問・要望',
    chatReplyingToLabel: (senderLabel) => '$senderLabelへの返信',
    chatEditingLabel: 'メッセージを編集中',
    chatUnsendConfirmTitle: '送信を取り消しますか？',
    chatUnsendConfirmMessage:
        'このメッセージは相手の画面からも完全に削除されます。既読・リアクション等も含めて痕跡は残りません。この操作は取り消せません。',
    chatUnsendConfirmButton: '取り消す',
    chatAttachFile: 'ファイル',
    chatAttachImage: '画像',
    chatAttachVideo: '動画',
    chatAttachCapture: '撮影',
    chatNoStickersMessage: 'まだペタピタがありません',
    stickerPackNotFoundMessage: 'このペタピタは見つかりませんでした',
    stickerSearchHint: 'ペタピタを検索',
    settingsStickersSection: 'ペタピタ',
    settingsManageOwnedStickers: '所持しているペタピタを管理',
    ownedStickersScreenTitle: '所持しているペタピタ',
    uninstallStickerButton: 'アンインストール',
    uninstallStickerConfirmTitle: 'アンインストールしますか？',
    uninstallStickerConfirmMessage: 'アンインストールすると、このペタピタは送信できなくなります。',
    uninstallStickerConfirmButton: 'アンインストールする',
    chatAttachmentTooLargeMessage: '2GBを超えるファイルは送信できません',
    chatAttachmentBlockedExtensionMessage: 'この拡張子のファイルは送信できません',
    chatAttachmentSendFailedMessage: '送信に失敗しました',
    chatResendAction: '再送',
    cancel: 'キャンセル',
    add: '追加',
    save: '保存',
    done: '完了',
    delete: '削除',
    profileIconSection: 'アイコン',
    profileBackgroundSection: '背景画像',
    profileNicknameHint: (term) => '友達には、Rhing IDの代わりにここで選んだ$termが表示されます。',
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
    enmusubiInviteLinkDescription: 'このリンクを知っている住人が開くと、あなたに仲間申請を送れます。',
    enmusubiCopyLink: 'コピー',
    enmusubiQrTitle: 'QRコードで交換',
    enmusubiQrDescription: '対面でQRコードを読み取ると、素早く仲間になれます。',
    enmusubiScanButton: 'QRコードを読み取る',
    enmusubiScanScreenTitle: 'QRコードを読み取る',
    inviteScreenTitle: '仲間申請',
    inviteConfirmDescriptionTemplate: (rhingId) => '@$rhingIdの住人に仲間申請を送りますか？',
    inviteScreenSendButton: '仲間申請を送る',
    inviteScreenGoHome: 'ホームに戻る',
    inviteScreenInvalid: 'このリンクは無効です',
    groupMenuProfileCard: 'プロフィールカード',
    groupMenuMemberList: 'メンバー一覧',
    groupMenuCreateInvite: '招待リンク作成',
    groupMenuManageRoles: 'ロール管理',
    groupMenuLeave: '退会',
    groupRoleListEmpty: 'まだロールがありません',
    groupRoleCreateDialogTitle: 'ロールを追加',
    groupRoleEditDialogTitle: 'ロールを編集',
    groupRoleDialogNameLabel: 'ロール名',
    groupRoleColorInvalid: '「#RRGGBB」の形式で入力してください',
    groupRoleColorNone: '色を設定しない',
    groupRolePermissionsLabel: '権限',
    groupPermissionLabel: (permission) => switch (permission) {
      'manageRooms' => '寄合の管理（作成・削除）',
      'manageRoles' => 'ロールの管理（作成・編集・削除・付与）',
      'manageReadReceipts' => '既読機能のオン/オフ',
      'manageJoinRequests' => '参加リクエストの承認・却下',
      'createInvite' => '招待リンクの作成',
      _ => permission,
    },
    groupRoleEveryoneNote: 'このロールは全員に自動で適用されます。削除・名前の変更はできません',
    groupRoleDeleteConfirmTitle: 'このロールを削除しますか？',
    groupRoleDeleteConfirmButton: '削除する',
    groupRoleNoneLabel: 'ロール未設定',
    groupRolePickerTitle: 'ロールを選択',
    groupRoleMembersLabel: 'メンバー',
    groupRoleAssignAllLabel: '全員に付与',
    groupRolePriorityTitle: 'ロールの優先順位',
    groupRolePriorityHint: '上にあるロールほど呼び名の色が優先されます',
    groupRoomRolePriorityMenuItem: 'この寄合の色優先順位を設定',
    groupRoomRolePriorityResetButton: '広場全体の設定に戻す',
    groupMenuEnableMultipleRooms: '寄合を複数扱う',
    dmMenuEnableMultipleRooms: '寄合を増やす',
    groupSettingsDefaultMuteLabel: '通知オフ（既定）',
    groupSettingsDefaultMuteHint: '寄合ごとに「この寄合独自の設定」をオンにすると個別に上書きできます',
    groupSettingsDefaultReadReceiptsLabel: '既読機能（既定）',
    groupSettingsDefaultReadReceiptsHint: '寄合ごとに「この寄合独自の設定」をオンにすると個別に上書きできます',
    groupRoomCustomSettingsLabel: 'この寄合独自の設定',
    groupRoomCustomSettingsHint:
        'オンにすると、通知・既読・ロールの優先順位を広場全体の設定より優先してこの寄合だけ個別に設定できます',
    groupSettingsDisableMultipleRoomsLabel: '寄合複数機能をオフにする',
    groupSettingsDisableMultipleRoomsHint: '複数の寄合機能をオフにし、この1つの寄合だけの広場に戻します',
    groupSettingsDisableMultipleRoomsBlockedHint: '寄合が複数あるため、1つにまとめてからオフにできます',
    groupSettingsDisableMultipleRoomsConfirmTitle: '寄合複数機能をオフにしますか？',
    groupSettingsDisableMultipleRoomsConfirmMessage:
        'このサイドバー・複数寄合機能が無くなり、以後の設定は寄合のハンバーガーメニューから行うことになります。',
    groupSettingsDisableMultipleRoomsConfirmButton: 'オフにする',
    profileCardPickerLabel: '使うプロフィールカード',
    profileCardPickerStandardOption: '標準',
    profileCardPickerStandardOptionWithName: (name) => '標準（$name）',
    settingsProfileCardAssignmentTitle: '会話ごとのプロフィールカード',
    settingsProfileCardAssignmentHint:
        '標準カード以外を使っている語らいだけがここに表示されます。＋から新しく設定できます。',
    settingsProfileCardAssignmentEmpty: '標準以外のカードを使っている語らいはまだありません',
    conversationProfileCardMenuLabel: '自分のプロフィールカード',
    workshopConversationCardAddDialogTitle: 'カードを個別に設定する語らいを選ぶ',
    workshopConversationCardAddEmpty: '設定できる語らいがありません',
    workshopConversationCardSearchHint: '名前で検索',
    groupSettingsTooltip: '広場自体の設定',
    groupTransferOwnershipMenuItem: '長を譲渡する',
    groupTransferOwnershipConfirmTitle: '長を譲渡しますか？',
    groupTransferOwnershipConfirmMessage: '再度長になるには譲渡してもらう必要があります。',
    groupTransferOwnershipConfirmButton: '譲渡',
    groupProfileCardNameLabel: '広場名',
    groupProfileCardDescriptionLabel: '一言',
    groupMemberListTitle: 'メンバー一覧',
    groupMemberListPendingSection: '参加リクエスト',
    groupMemberListMembersSection: 'メンバー',
    groupInviteDialogTitle: '招待リンク',
    groupInviteDialogDescription: 'このリンクを知っている人が開くと、長の承認を経てこの広場に参加できます。',
    groupLeaveConfirmTitle: '広場から退会しますか？',
    groupLeaveConfirmMessage: '退会すると、この広場のメッセージは見られなくなります。',
    groupLeaveButton: '退会する',
    groupLeaveOwnerError: '長（オーナー）は退会できません',
    groupDeleteMenuLabel: '広場を削除',
    groupDeleteConfirmTitle: '広場を削除しますか？',
    groupDeleteConfirmMessage:
        '削除すると全ての寄合・メッセージ・ロールが完全に失われ、元に戻せません。'
        '参加している全員がこの広場にアクセスできなくなります。長のみ実行できます。',
    groupDeleteButton: '削除する',
    groupJoinScreenTitle: '広場への参加',
    groupJoinInvalid: 'この招待リンクは無効です',
    groupJoinAlreadyMember: '既にこの広場のメンバーです',
    groupJoinPending: '参加リクエストを送信済みです。長の承認をお待ちください',
    groupJoinDescriptionTemplate: (groupName) =>
        '「$groupName」への参加をリクエストしますか？長が承認すると参加できます。',
    groupJoinRequestButton: '参加をリクエストする',
    groupJoinRequestSent: '参加リクエストを送信しました。長の承認をお待ちください',
    groupJoinOpenGroup: '広場を開く',
    groupJoinRetry: '再読み込み',
    settingsDeleteAccountConfirmTitle: 'アカウントを削除しますか？',
    settingsDeleteAccountGraceOption: '30日後に削除',
    settingsDeleteAccountGraceOptionSubtitle: '30日以内に再ログインすれば取り消せます',
    settingsDeleteAccountImmediate: '今すぐ削除',
    settingsDeleteAccountImmediateOptionSubtitle: 'この操作は取り消せません',
    settingsDeleteAccountCancelButton: 'やめる',
    accountDeleteOwnerGuardTitle: '広場の長を譲渡してください',
    accountDeleteOwnerGuardMessage:
        '以下の広場で長を務めています。アカウントを削除する前に、'
        'それぞれ別のメンバーへ長を譲渡してください。',
    accountDeleteOwnerGuardCleared: '全ての広場で長を譲渡しました。削除を続けられます。',
    accountDeleteOwnerGuardContinue: '続ける',
    accountRestoreTitle: 'アカウントを復元しますか？',
    accountRestoreMessage: (remainingDays) =>
        'あと$remainingDays日で、サーバーから全ての情報が完全に削除されます。',
    accountRestoreButton: 'アカウントを復元する',
    accountRestoreSignOutButton: 'サインアウト',
    accountSuspendedTitle: 'アカウントが停止されています',
    accountSuspendedMessage: '運営により、このアカウントは利用を停止されています。',
    accountSuspendedSignOutButton: 'サインアウト',
    chatAccountDeletedNotice: (label) => '$labelがアカウントを削除しました。',
    chatAccountDeletedDeleteConversationPrompt: '語らいを削除しますか？',
    chatAccountDeletedYesButton: 'はい',
    chatAccountDeletedNoButton: 'いいえ',
    chatAccountDeletedConfirmTitle: '本当によろしいですか？',
    chatAccountDeletedConfirmButton: '削除する',
    chatNoMoreHistory: 'これ以上の履歴はありません',
    roomListAddDialogTitle: (term) => '$termを追加',
    roomListAddButton: '追加',
    roomListDeleteConfirmTitle: (term) => 'この$termを削除しますか？',
    roomListDeleteConfirmButton: '削除',
    roomRenameLabel: (term) => '$termの名前を変更',
    roomMenuDeleteLabel: (term) => '$termを削除',
    roomDeleteLastRoomError: '最後の1つの寄合は削除できません',
    dmMenuDeleteConversation: (term) => '$termの削除',
    chatAddToAlbumAction: 'アルバムに登録',
    albumButtonTooltip: 'アルバム',
    albumListTitle: 'アルバム',
    albumListEmptyMessage: 'まだアルバムがありません',
    albumCreateButtonLabel: '新しいアルバム',
    albumCreateDialogTitle: 'アルバムを作成',
    albumNameFieldHint: 'アルバム名',
    albumRenameAction: '名前を変更',
    albumRenameDialogTitle: 'アルバム名を変更',
    albumDeleteAction: 'アルバムを削除',
    albumDeleteConfirmTitle: 'アルバムを削除しますか？',
    albumDeleteConfirmMessage: 'このアルバム内の画像・動画もすべて削除されます。この操作は取り消せません。',
    albumItemCountLabel: (count) => '$count件',
    albumRemoveItemAction: 'アルバムから削除',
    albumRemoveItemConfirmTitle: 'アルバムから削除しますか？',
    albumRemoveItemConfirmMessage: 'この操作は取り消せません。',
    albumPickerTitle: 'アルバムに登録',
    albumPickerCreateNewOption: '新しいアルバムを作成',
    albumAddedSnackbarMessage: 'アルバムに登録しました',
    albumAddFailedSnackbarMessage: 'アルバムへの登録に失敗しました',
    commonCreate: '作成',
  );

  static final enGB = Strings._(
    navTalk: 'Talks',
    navProfile: 'Profile',
    navSettings: 'Settings',
    addMenuDmTitleTemplate: (dmTerm) => 'Start a $dmTerm',
    addMenuDmSubtitle: 'Add someone to talk to one-on-one',
    addMenuGroupTitleTemplate: (plazaTerm) => 'Create a $plazaTerm',
    addMenuGroupSubtitle: 'Make a group with three or more people',
    talksSearchHint: 'Search talks',
    talksSearchNoResults: 'No matches found',
    settingsFolderAccount: 'Account',
    settingsFolderApplication: 'Application',
    settingsFolderDesign: 'Colour',
    settingsFolderLanguage: 'Language',
    settingsFolderNotifications: 'Notifications',
    settingsFolderTalk: 'Talk',
    settingsFolderSupport: 'Support',
    settingsBlockedUsersTitle: 'Blocked users',
    settingsBlockedUsersEmpty: 'No blocked users',
    settingsBlockedUsersUnblock: 'Unblock',
    settingsAccentColor: 'Accent colour',
    settingsAccentColorGekigaHint:
        'Used as the background colour in Gekiga UI style '
        '(defaults to the current red).',
    settingsAppearanceGekigaLockedHint:
        'Cannot be changed while the Gekiga UI style is selected',
    settingsAppearance: 'Appearance',
    settingsAppearanceLight: 'Light',
    settingsAppearanceDark: 'Dark',
    settingsAppearanceSystem: 'Match device',
    settingsColorCode: 'Colour code',
    settingsColorPresets: 'Presets',
    settingsCustomColors: 'Saved colours',
    settingsCustomColorRegister: 'Save this colour',
    settingsCustomColorLimitReachedTemplate: (max) =>
        'You can save up to $max colours',
    settingsCustomColorDeleteConfirmTitle: 'Delete this colour?',
    settingsCustomColorDeleteConfirmButton: 'Delete',
    settingsLogout: 'Log out',
    settingsDisplayLanguage: 'Display language',
    settingsTimeFormat: 'Message time display',
    settingsTimeFormat24h: '24-hour',
    settingsTimeFormat12h: '12-hour',
    settingsSubUI: 'UI',
    settingsUIDescription: 'Choose how the whole app looks.',
    settingsUiStyleFlatLabel: 'Flat',
    settingsUiStyleFlatDescription: 'The current standard style',
    settingsUiStyleGekigaLabel: 'Gekiga',
    settingsUiStyleGekigaDescription:
        'A hand-drawn, thick jagged-line, monochrome speech-bubble look.',
    settingsUiStyleGlassLabel: 'Glass',
    settingsUiStyleGlassDescription: 'Frosted, glowing-edge style',
    settingsChatLayoutTitle: 'Message display',
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
    settingsAccountInfoSection: 'Account information',
    settingsRhingIdLabel: 'Rhing ID',
    settingsSecurity: 'Security',
    settingsPassword: 'Password',
    settingsTwoFactor: 'Two-factor authentication',
    twoFactorEnabledStatus: 'Enabled',
    twoFactorDisabledStatus: 'Disabled',
    twoFactorSetupDialogTitle: 'Set up two-factor authentication',
    twoFactorSetupDescription:
        'Scan the QR code with an authenticator app (e.g. Google Authenticator), or enter the secret key manually, then enter the 6-digit code shown.',
    twoFactorSecretKeyLabel: 'Secret key (manual entry)',
    twoFactorCodeLabel: '6-digit code',
    twoFactorEnrollButton: 'Enable',
    twoFactorInvalidCodeError: 'That code is not correct',
    twoFactorDisableConfirmTitle: 'Disable two-factor authentication?',
    twoFactorDisableConfirmMessage:
        'You will no longer be asked for a code when signing in.',
    twoFactorDisableConfirmButton: 'Disable',
    twoFactorRequiresRecentLoginError:
        'Please sign in again to confirm, then try again.',
    twoFactorReauthenticateButton: 'Sign in again',
    twoFactorChallengeTitle: 'Enter authenticator code',
    twoFactorChallengeDescription:
        'Enter the 6-digit code shown in your authenticator app.',
    twoFactorChallengeConfirmButton: 'Confirm',
    qrLoginDialogTitle: 'Sign in with a QR code',
    qrLoginDialogDescription:
        "Open DaiDai on a device where you're already signed in, then go to "
        'Settings > Account > Security > Sign in with a QR code and scan this.',
    qrLoginExpiredMessage: 'This QR code has expired',
    qrLoginRefreshButton: 'Refresh',
    qrLoginSignInError: 'Sign-in failed',
    qrLoginScanConfirmTitle: 'Allow sign-in on this device?',
    qrLoginScanConfirmMessage: "If you don't recognize this, don't allow it.",
    qrLoginScanConfirmButton: 'Allow',
    qrLoginInvalidQrError: 'Invalid QR code',
    qrLoginApproveError: 'Approval failed. The QR code may have expired.',
    qrLoginScanInstructionMessage:
        'On another device, open the sign-in screen and tap "Sign in with a '
        'QR code", then scan the code it shows with this device.',
    qrLoginScanInstructionButton: 'Start scanning',
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
    settingsAdvancedSectionTitle: 'Advanced settings',
    settingsStickerSendModeTitle: 'Sticker sending method',
    settingsStickerSendModeLine: 'Tap twice to send (LINE-style)',
    settingsStickerSendModeLineSubtitle:
        'The first tap shows an enlarged preview; tap the same sticker again to send it',
    settingsStickerSendModeDiscord: 'Tap once to send (Discord-style)',
    settingsStickerSendModeDiscordSubtitle:
        'Tapping a sticker sends it immediately',
    settingsDraftSyncTitle: 'Sync drafts across devices',
    settingsDraftSyncSubtitle:
        'Restores in-progress message text when you open the same conversation on another device',
    back: 'Back',
    friendSearchTitle: 'Add a friend',
    friendSearchHint:
        "Enter the other person's Rhing ID to send a friend request. "
        'Once accepted, you can start talking.',
    friendSearchLabel: "Their Rhing ID",
    friendSearchButton: 'Send request',
    friendSearchSearchButton: 'Search',
    friendSearchNotFound: 'No resident found with that Rhing ID',
    friendSearchSelf: "You can't send a request to yourself",
    friendRequestSent: 'Friend request sent',
    friendRequestAlreadySent: 'Request already pending',
    friendRequestAlreadyFriends: 'Already friends',
    friendRequestAccept: 'Accept',
    friendRequestDecline: 'Decline',
    userProfileCardSendRequest: 'Send friend request',
    userProfileCardAcceptRequest: 'Accept friend request',
    userProfileCardRequestPending: 'Request sent. Waiting for approval.',
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
    conversationReadReceiptsDisableConfirmTitle: 'Turn off read receipts?',
    conversationReadReceiptsDisableConfirmMessage:
        'Turning this off will delete all existing read receipt history.',
    conversationReadReceiptsDisableConfirmButton: 'Turn off',
    conversationReadReceiptsProposeDisable: 'Propose turning off read receipts',
    conversationReadReceiptsProposeEnable: 'Propose turning on read receipts',
    conversationReadReceiptsBannerWaitingOff:
        'Waiting for approval to turn off read receipts',
    conversationReadReceiptsBannerWaitingOn:
        'Waiting for approval to turn on read receipts',
    conversationReadReceiptsBannerProposedOff: (senderLabel) =>
        '$senderLabel proposed turning off read receipts. Allow it?',
    conversationReadReceiptsBannerProposedOn: (senderLabel) =>
        '$senderLabel proposed turning on read receipts. Allow it?',
    conversationReadReceiptsBannerAcceptButton: 'Allow',
    conversationReadReceiptsBannerDeclineButton: "Don't allow",
    conversationReadReceiptsBannerCancelButton: 'Cancel',
    conversationProposeSeverance: 'Propose severance',
    severanceProposeDialogTitle: 'Propose severance?',
    severanceProposeDialogMessage:
        "If the other person agrees, all conversation history will be "
        "permanently deleted and you'll no longer be friends. Nothing "
        "happens until they agree.",
    severanceProposeButton: 'Propose',
    severanceAcceptDialogTitle: 'Agree to severance?',
    severanceAcceptDialogMessage:
        'Agreeing will permanently delete all conversation history and '
        "end your friendship. This can't be undone.",
    severanceAcceptButton: 'Agree and delete',
    severanceBannerWaitingForOther:
        'Severance proposed. Waiting for the other person to agree.',
    severanceBannerCancelButton: 'Cancel',
    severanceBannerProposedByOther: 'The other person proposed severance',
    severanceBannerDeclineButton: 'Not now',
    severanceBannerAcceptButton: 'Agree',
    readReceiptPopupTitle: 'Read by',
    reactionListPopupTitle: 'Reactions',
    chatSelectionModeTitle: (count) => '$count selected',
    chatDeleteConfirmTitle: 'Delete these messages?',
    chatDeleteConfirmMessage:
        "The selected messages will disappear from your account only "
        "(others can still see them). Once everyone has deleted the same "
        "messages, they'll be permanently deleted from the server. This "
        "can't be undone.",
    chatDeleteConfirmButton: 'Delete',
    chatReplyAction: 'Reply',
    chatEditAction: 'Edit',
    chatUnsendAction: 'Unsend',
    chatReactAction: 'React',
    chatCopyAction: 'Copy',
    chatPartialCopyAction: 'Partial copy',
    chatSelectAction: 'Delete messages',
    chatPinAction: 'Pin',
    chatUnpinAction: 'Unpin',
    chatPinnedMessagesTooltip: 'Pinned messages',
    chatPinnedMessagesEmpty: 'No pinned messages',
    chatScreenshotAction: 'Screenshot',
    chatScreenshotSelectionModeTitle: (count) => '$count to capture',
    chatScreenshotDialogTitle: 'Take screenshot',
    chatScreenshotBlurCheckboxLabel: 'Blur names and avatars',
    chatScreenshotConfirmButton: 'Capture',
    chatScreenshotErrorMessage: 'Failed to create the screenshot.',
    chatEditedLabel: 'Edited',
    chatInputHint: 'Type a message...',
    announcementContactFormLabel: 'Questions & Feedback',
    chatReplyingToLabel: (senderLabel) => 'Replying to $senderLabel',
    chatEditingLabel: 'Editing message',
    chatUnsendConfirmTitle: 'Unsend this message?',
    chatUnsendConfirmMessage:
        "This message will be completely removed from the other person's "
        "screen too (including read receipts and reactions). This can't "
        "be undone.",
    chatUnsendConfirmButton: 'Unsend',
    chatAttachFile: 'File',
    chatAttachImage: 'Image',
    chatAttachVideo: 'Video',
    chatAttachCapture: 'Capture',
    chatNoStickersMessage: "You don't have any stickers yet.",
    stickerPackNotFoundMessage: "This sticker couldn't be found.",
    stickerSearchHint: 'Search stickers',
    settingsStickersSection: 'Stickers',
    settingsManageOwnedStickers: 'Manage owned stickers',
    ownedStickersScreenTitle: 'Owned stickers',
    uninstallStickerButton: 'Uninstall',
    uninstallStickerConfirmTitle: 'Uninstall this pack?',
    uninstallStickerConfirmMessage:
        "You won't be able to send these stickers after uninstalling.",
    uninstallStickerConfirmButton: 'Uninstall',
    chatAttachmentTooLargeMessage: "Files over 2GB can't be sent.",
    chatAttachmentBlockedExtensionMessage: "This file type can't be sent.",
    chatAttachmentSendFailedMessage: 'Failed to send.',
    chatResendAction: 'Resend',
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
    groupMenuManageRoles: 'Manage roles',
    groupMenuLeave: 'Leave',
    groupRoleListEmpty: 'No roles yet',
    groupRoleCreateDialogTitle: 'Add role',
    groupRoleEditDialogTitle: 'Edit role',
    groupRoleDialogNameLabel: 'Role name',
    groupRoleColorInvalid: 'Enter in "#RRGGBB" format',
    groupRoleColorNone: 'No colour',
    groupRolePermissionsLabel: 'Permissions',
    groupPermissionLabel: (permission) => switch (permission) {
      'manageRooms' => 'Manage rooms (create/delete)',
      'manageRoles' => 'Manage roles (create/edit/delete/assign)',
      'manageReadReceipts' => 'Toggle read receipts',
      'manageJoinRequests' => 'Approve/decline join requests',
      'createInvite' => 'Create invite links',
      _ => permission,
    },
    groupRoleEveryoneNote:
        'This role applies to everyone automatically. It cannot be deleted or renamed',
    groupRoleDeleteConfirmTitle: 'Delete this role?',
    groupRoleDeleteConfirmButton: 'Delete',
    groupRoleNoneLabel: 'No role',
    groupRolePickerTitle: 'Select a role',
    groupRoleMembersLabel: 'Members',
    groupRoleAssignAllLabel: 'Assign to everyone',
    groupRolePriorityTitle: 'Role priority',
    groupRolePriorityHint:
        'Roles higher up take priority for the display name colour',
    groupRoomRolePriorityMenuItem: 'Set this room\'s colour priority',
    groupRoomRolePriorityResetButton: 'Reset to plaza default',
    groupMenuEnableMultipleRooms: 'Enable multiple rooms',
    dmMenuEnableMultipleRooms: 'Add more rooms',
    groupSettingsDefaultMuteLabel: 'Mute (default)',
    groupSettingsDefaultMuteHint:
        'Rooms can override this individually with "This room\'s own settings"',
    groupSettingsDefaultReadReceiptsLabel: 'Read receipts (default)',
    groupSettingsDefaultReadReceiptsHint:
        'Rooms can override this individually with "This room\'s own settings"',
    groupRoomCustomSettingsLabel: "This room's own settings",
    groupRoomCustomSettingsHint:
        'When on, this room\'s notification, read receipts, and role priority settings take priority over the plaza defaults',
    groupSettingsDisableMultipleRoomsLabel: 'Merge back into a single room',
    groupSettingsDisableMultipleRoomsHint:
        'Turns off multiple rooms and returns this plaza to a single room',
    groupSettingsDisableMultipleRoomsBlockedHint:
        'You can turn this off once only one room remains',
    groupSettingsDisableMultipleRoomsConfirmTitle:
        'Merge back into a single room?',
    groupSettingsDisableMultipleRoomsConfirmMessage:
        'This sidebar and multiple-room feature will be removed, and settings will move back to the room\'s hamburger menu.',
    groupSettingsDisableMultipleRoomsConfirmButton: 'Merge',
    profileCardPickerLabel: 'Profile card to use',
    profileCardPickerStandardOption: 'Standard',
    profileCardPickerStandardOptionWithName: (name) => 'Standard ($name)',
    settingsProfileCardAssignmentTitle: 'Profile card per conversation',
    settingsProfileCardAssignmentHint:
        'Only conversations using a non-standard card are shown here. Tap + to set one up.',
    settingsProfileCardAssignmentEmpty:
        'No conversations are using a non-standard card yet',
    conversationProfileCardMenuLabel: 'My profile card',
    workshopConversationCardAddDialogTitle:
        'Choose a conversation to set a card for',
    workshopConversationCardAddEmpty: 'No conversations available to set',
    workshopConversationCardSearchHint: 'Search by name',
    groupSettingsTooltip: 'Plaza settings',
    groupTransferOwnershipMenuItem: 'Transfer ownership',
    groupTransferOwnershipConfirmTitle: 'Transfer ownership?',
    groupTransferOwnershipConfirmMessage:
        'You will need to be given ownership again to become the owner once more.',
    groupTransferOwnershipConfirmButton: 'Transfer',
    groupProfileCardNameLabel: 'Plaza name',
    groupProfileCardDescriptionLabel: 'Status',
    groupMemberListTitle: 'Members',
    groupMemberListPendingSection: 'Join requests',
    groupMemberListMembersSection: 'Members',
    groupInviteDialogTitle: 'Invite link',
    groupInviteDialogDescription:
        'Anyone who opens this link can request to join this plaza, '
        'subject to approval by the owner.',
    groupLeaveConfirmTitle: 'Leave this plaza?',
    groupLeaveConfirmMessage:
        "You won't be able to see this plaza's messages after leaving.",
    groupLeaveButton: 'Leave',
    groupLeaveOwnerError: 'The owner cannot leave',
    groupDeleteMenuLabel: 'Delete plaza',
    groupDeleteConfirmTitle: 'Delete this plaza?',
    groupDeleteConfirmMessage:
        'All rooms, messages, and roles will be permanently lost and this '
        'cannot be undone. Every member will lose access to this plaza. '
        'Only the owner can do this.',
    groupDeleteButton: 'Delete',
    groupJoinScreenTitle: 'Join plaza',
    groupJoinInvalid: 'This invite link is invalid',
    groupJoinAlreadyMember: "You're already a member of this plaza",
    groupJoinPending: "You've already requested to join. Waiting for approval.",
    groupJoinDescriptionTemplate: (groupName) =>
        'Request to join "$groupName"? '
        'You can join once the owner approves.',
    groupJoinRequestButton: 'Request to join',
    groupJoinRequestSent: 'Join request sent. Waiting for approval.',
    groupJoinOpenGroup: 'Open plaza',
    groupJoinRetry: 'Retry',
    settingsDeleteAccountConfirmTitle: 'Delete your account?',
    settingsDeleteAccountGraceOption: 'Delete after 30 days',
    settingsDeleteAccountGraceOptionSubtitle:
        'Undo by logging back in within 30 days',
    settingsDeleteAccountImmediate: 'Delete immediately',
    settingsDeleteAccountImmediateOptionSubtitle:
        'This action cannot be undone',
    settingsDeleteAccountCancelButton: 'Cancel',
    accountDeleteOwnerGuardTitle: 'Transfer ownership first',
    accountDeleteOwnerGuardMessage:
        'You are the owner of the plazas below. Please transfer ownership '
        'to another member of each one before deleting your account.',
    accountDeleteOwnerGuardCleared:
        'Ownership transferred for all plazas. You can continue.',
    accountDeleteOwnerGuardContinue: 'Continue',
    accountRestoreTitle: 'Restore your account?',
    accountRestoreMessage: (remainingDays) =>
        'All your data will be permanently deleted from our servers in '
        '$remainingDays day(s).',
    accountRestoreButton: 'Restore account',
    accountRestoreSignOutButton: 'Sign out',
    accountSuspendedTitle: 'Your account has been suspended',
    accountSuspendedMessage: 'This account has been suspended by the operator.',
    accountSuspendedSignOutButton: 'Sign out',
    chatAccountDeletedNotice: (label) => '$label deleted their account.',
    chatAccountDeletedDeleteConversationPrompt: 'Delete this conversation?',
    chatAccountDeletedYesButton: 'Yes',
    chatAccountDeletedNoButton: 'No',
    chatAccountDeletedConfirmTitle: 'Are you sure?',
    chatAccountDeletedConfirmButton: 'Delete',
    chatNoMoreHistory: 'No more history',
    roomListAddDialogTitle: (term) => 'Add $term',
    roomListAddButton: 'Add',
    roomListDeleteConfirmTitle: (term) => 'Delete this $term?',
    roomListDeleteConfirmButton: 'Delete',
    roomRenameLabel: (term) => 'Rename $term',
    roomMenuDeleteLabel: (term) => 'Delete $term',
    roomDeleteLastRoomError: 'The last remaining room cannot be deleted.',
    dmMenuDeleteConversation: (term) => 'Delete $term',
    chatAddToAlbumAction: 'Add to album',
    albumButtonTooltip: 'Album',
    albumListTitle: 'Album',
    albumListEmptyMessage: 'No albums yet',
    albumCreateButtonLabel: 'New album',
    albumCreateDialogTitle: 'Create album',
    albumNameFieldHint: 'Album name',
    albumRenameAction: 'Rename',
    albumRenameDialogTitle: 'Rename album',
    albumDeleteAction: 'Delete album',
    albumDeleteConfirmTitle: 'Delete this album?',
    albumDeleteConfirmMessage:
        'All images and videos in this album will also be deleted. This cannot be undone.',
    albumItemCountLabel: (count) => '$count items',
    albumRemoveItemAction: 'Remove from album',
    albumRemoveItemConfirmTitle: 'Remove from this album?',
    albumRemoveItemConfirmMessage: 'This cannot be undone.',
    albumPickerTitle: 'Add to album',
    albumPickerCreateNewOption: 'Create new album',
    albumAddedSnackbarMessage: 'Added to album',
    albumAddFailedSnackbarMessage: 'Failed to add to album',
    commonCreate: 'Create',
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
