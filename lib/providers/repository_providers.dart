import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../repositories/announcement_repository.dart';
import '../repositories/turn_credentials_repository.dart';
import '../repositories/album_repository.dart';
import '../repositories/auth_repository.dart';
import '../repositories/block_repository.dart';
import '../repositories/contact_alias_repository.dart';
import '../repositories/residence_repository.dart';
import '../repositories/calendar_category_repository.dart';
import '../repositories/calendar_event_repository.dart';
import '../repositories/call_repository.dart';
import '../repositories/conversation_prefs_repository.dart';
import '../repositories/direct_message_repository.dart';
import '../repositories/friend_repository.dart';
import '../repositories/group_call_repository.dart';
import '../repositories/group_repository.dart';
import '../models/group_profile_card.dart';
import '../models/link_preview.dart';
import '../repositories/link_preview_repository.dart';
import '../repositories/note_repository.dart';
import '../repositories/passcode_repository.dart';
import '../repositories/poll_repository.dart';
import '../repositories/push_notification_repository.dart';
import '../repositories/schedule_coordination_repository.dart';
import '../repositories/spam_config_repository.dart';
import '../repositories/sticker_repository.dart';
import '../repositories/user_repository.dart';
import '../repositories/bot_repository.dart';
import '../repositories/scheduled_message_repository.dart';
import '../repositories/webhook_repository.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return FirebaseAuthRepository();
});

final userRepositoryProvider = Provider<UserRepository>((ref) {
  return FirestoreUserRepository();
});

/// アプリ起動時のパスコードロック機能（2026-09-11追加）。他のRepositoryと
/// 違いFirebaseに依存せず端末ローカルのみで完結するが、置き場所は他と
/// 統一してここに集約する。
final passcodeRepositoryProvider = Provider<PasscodeRepository>((ref) {
  return SecureStoragePasscodeRepository();
});

final directMessageRepositoryProvider = Provider<DirectMessageRepository>((
  ref,
) {
  return FirestoreDirectMessageRepository();
});

final groupRepositoryProvider = Provider<GroupRepository>((ref) {
  return FirestoreGroupRepository();
});

final scheduledMessageRepositoryProvider = Provider<ScheduledMessageRepository>(
  (ref) {
    return FirestoreScheduledMessageRepository();
  },
);

final callRepositoryProvider = Provider<CallRepository>((ref) {
  return FirestoreCallRepository();
});

final groupCallRepositoryProvider = Provider<GroupCallRepository>((ref) {
  return FirestoreGroupCallRepository();
});

final friendRepositoryProvider = Provider<FriendRepository>((ref) {
  return FirestoreFriendRepository();
});

final spamConfigRepositoryProvider = Provider<SpamConfigRepository>((ref) {
  return FirestoreSpamConfigRepository();
});

/// クライアント側スパムチェック（技術仕様書8.3レイヤー3）用のキーワード
/// 一覧。未取得の間・エラー時は空リストとして扱う（キーワードが引けない
/// からといって送信をブロックしない方針、2026-09-07追加）。
final spamKeywordsProvider = StreamProvider<List<String>>((ref) {
  return ref.watch(spamConfigRepositoryProvider).watchSpamKeywords();
});

final conversationPrefsRepositoryProvider =
    Provider<ConversationPrefsRepository>((ref) {
      return FirestoreConversationPrefsRepository();
    });

final blockRepositoryProvider = Provider<BlockRepository>((ref) {
  return FirestoreBlockRepository();
});

final contactAliasRepositoryProvider = Provider<ContactAliasRepository>((ref) {
  return FirestoreContactAliasRepository();
});

final residenceRepositoryProvider = Provider<ResidenceRepository>((ref) {
  return FirestoreResidenceRepository();
});

final linkPreviewRepositoryProvider = Provider<LinkPreviewRepository>((ref) {
  return InviteAwareLinkPreviewRepository(
    inner: HttpLinkPreviewRepository(),
    userPreview: (url, rhingSeed) async {
      final user = await ref
          .read(userRepositoryProvider)
          .findByRhingSeed(rhingSeed);
      if (user == null) return null;
      // 題名・説明は付けない（カードの中に呼び名・一言が出る為）。
      return LinkPreview(url: url, inviteUser: user);
    },
    groupPreview: (url, groupId) async {
      final group = await ref
          .read(groupRepositoryProvider)
          .getInvitePreview(groupId);
      if (group == null) return null;
      return LinkPreview(
        url: url,
        inviteGroup: GroupProfileCard(
          name: group.name,
          description: group.description,
          iconUrl: group.iconUrl,
          backgroundImageUrl: group.backgroundImageUrl,
          iconFocal: group.iconFocal,
          backgroundFocal: group.backgroundFocal,
        ),
      );
    },
  );
});

final stickerRepositoryProvider = Provider<StickerRepository>((ref) {
  return FirestoreStickerRepository();
});

final albumRepositoryProvider = Provider<AlbumRepository>((ref) {
  return FirestoreAlbumRepository();
});

final calendarEventRepositoryProvider = Provider<CalendarEventRepository>((
  ref,
) {
  return FirestoreCalendarEventRepository();
});

final calendarCategoryRepositoryProvider = Provider<CalendarCategoryRepository>(
  (ref) {
    return FirestoreCalendarCategoryRepository();
  },
);

final scheduleCoordinationRepositoryProvider =
    Provider<ScheduleCoordinationRepository>((ref) {
      return FirestoreScheduleCoordinationRepository();
    });

final pollRepositoryProvider = Provider<PollRepository>((ref) {
  return FirestorePollRepository();
});

/// お便り（運営から全住人への配信、2026-10-10追加）。
final turnCredentialsRepositoryProvider = Provider<TurnCredentialsRepository>((
  ref,
) {
  return FirebaseTurnCredentialsRepository();
});

final announcementRepositoryProvider = Provider<AnnouncementRepository>((ref) {
  return FirestoreAnnouncementRepository();
});

/// bot API（段階2a、2026-11-09追加）。
final botRepositoryProvider = Provider<BotRepository>((ref) {
  return FirestoreBotRepository();
});

/// 受信Webhook（bot・API段階1、2026-10-10追加）。
final webhookRepositoryProvider = Provider<WebhookRepository>((ref) {
  return FirestoreWebhookRepository();
});

final noteRepositoryProvider = Provider<NoteRepository>((ref) {
  return FirestoreNoteRepository();
});

final pushNotificationRepositoryProvider = Provider<PushNotificationRepository>(
  (ref) {
    return FirebaseMessagingPushNotificationRepository();
  },
);

final authStateProvider = StreamProvider<User?>((ref) {
  return ref.watch(authRepositoryProvider).authStateChanges();
});

/// 現在ログイン中ユーザーが管理者かどうか（管理画面向け、2026-08-12追加）。
/// [authStateProvider]を購読し、サインイン/サインアウトのたびに再評価する。
final isAdminProvider = FutureProvider<bool>((ref) async {
  ref.watch(authStateProvider);
  return ref.watch(authRepositoryProvider).isAdmin();
});
