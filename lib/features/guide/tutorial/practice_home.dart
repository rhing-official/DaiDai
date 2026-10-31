import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/strings.dart';
import '../../../l10n/tutorial_content.dart';
import '../../../providers/repository_providers.dart';
import '../../../router/back_stack.dart';
import '../../../widgets/nav_chip.dart';
import '../../chat/chat_panes.dart';
import '../../chat/talks_tab.dart';
import '../../../models/direct_message.dart';
import '../../profile/profile_tab.dart';
import '../../../providers/app_locale_provider.dart';
import '../../../providers/block_providers.dart';
import '../../../providers/conversation_prefs_providers.dart';
import '../../../providers/direct_message_providers.dart';
import '../../../providers/friend_providers.dart';
import '../../../providers/group_join_request_providers.dart';
import '../../../providers/user_providers.dart';
import '../../../providers/avatar_palette_provider.dart';
import 'practice_repositories.dart';
import 'tutorial_controller.dart';
import 'tutorial_target.dart';

/// 練習用のホーム（2026-10-17追加）。本物のナビチップ・語らいタブ・身だしなみタブを、
/// 偽のユーザー・偽の練習相手・書き込まないリポジトリを入れた入れ子の
/// [ProviderScope]の中で動かす。そのため一覧の見た目・チャットのレイアウト等、
/// ユーザーの設定に合った実際の画面のまま解説できる。
/// 画面にはユーザーに不要な説明（「練習モード」等）は出さない。
/// 本物のホームの状態・データには一切触れず、ガイドの案内の層が丸で示した場所
/// 以外は押せないため、ユーザーは道順を実際に押して覚えられる。
/// 戻る・進む履歴も専用のものに差し替え、本物の履歴を汚さない。
class PracticeHome extends ConsumerStatefulWidget {
  const PracticeHome({this.focus, this.topPadding = 48, super.key});

  /// 初期設定のプレビューで、どの画面を見せるか（2026-10-31追加）。nullなら
  /// ガイド用の従来の動き（台本の最初の手順で決まる）。
  final PracticeFocus? focus;

  /// 上の余白。ガイドの「やめる」ボタン（右上）が重ならないよう既定は48、
  /// 案内の層が無い初期設定のプレビューでは0にする。
  final double topPadding;

  @override
  ConsumerState<PracticeHome> createState() => _PracticeHomeState();
}

/// 初期設定のプレビューで見せる画面（[PracticeHome.focus]）。
enum PracticeFocus {
  /// 語らいの一覧。
  talksList,

  /// 練習用の会話を開いた状態。
  chat,
}

/// 練習用の画面で使うアイコン色の候補（`GeneratedAvatar.palette`から青緑を除いたもの）。
const practiceAvatarPalette = <Color>[
  Color(0xFFEE7800),
  Color(0xFF6D4C41),
  Color(0xFF5E35B1),
  Color(0xFF1E88E5),
  Color(0xFFD81B60),
];

class _PracticeHomeState extends ConsumerState<PracticeHome> {
  late final _dmRepository = PracticeDirectMessageRepository(
    greeting: practiceGreeting.of(ref.read(appLocaleProvider)),
  );
  late final _noteRepository = PracticeNoteRepository(
    title: practiceNoteTitle.of(ref.read(appLocaleProvider)),
  );

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [
        userRepositoryProvider.overrideWithValue(PracticeUserRepository()),
        directMessageRepositoryProvider.overrideWithValue(_dmRepository),
        groupRepositoryProvider.overrideWithValue(PracticeGroupRepository()),
        friendRepositoryProvider.overrideWithValue(PracticeFriendRepository()),
        blockRepositoryProvider.overrideWithValue(PracticeBlockRepository()),
        stickerRepositoryProvider.overrideWithValue(
          PracticeStickerRepository(),
        ),
        albumRepositoryProvider.overrideWithValue(PracticeAlbumRepository()),
        calendarEventRepositoryProvider.overrideWithValue(
          PracticeCalendarEventRepository(),
        ),
        calendarCategoryRepositoryProvider.overrideWithValue(
          PracticeCalendarCategoryRepository(),
        ),
        scheduleCoordinationRepositoryProvider.overrideWithValue(
          PracticeScheduleCoordinationRepository(),
        ),
        pollRepositoryProvider.overrideWithValue(PracticePollRepository()),
        noteRepositoryProvider.overrideWithValue(_noteRepository),
        callRepositoryProvider.overrideWithValue(PracticeCallRepository()),
        groupCallRepositoryProvider.overrideWithValue(
          PracticeGroupCallRepository(),
        ),
        spamKeywordsProvider.overrideWith((ref) => Stream.value(const [])),
        conversationPrefsRepositoryProvider.overrideWithValue(
          PracticeConversationPrefsRepository(),
        ),
        // リポジトリを読む「アプリ全体の」プロバイダーは、入れ子の差し替えが届かず
        // 本物のリポジトリを読んでしまうため、練習用の画面の中で作り直す。
        watchedUserProvider.overrideWith(
          (ref, id) => ref.watch(userRepositoryProvider).watchUser(id),
        ),
        watchedDmProvider.overrideWith(
          (ref, id) =>
              ref.watch(directMessageRepositoryProvider).watchDirectMessage(id),
        ),
        conversationPrefsProvider.overrideWith(
          (ref, id) =>
              ref.watch(conversationPrefsRepositoryProvider).watchAll(id),
        ),
        blockedUserIdsProvider.overrideWith(
          (ref, id) =>
              ref.watch(blockRepositoryProvider).watchBlockedUserIds(id),
        ),
        myGroupJoinRequestsProvider.overrideWith(
          (ref, id) =>
              ref.watch(groupRepositoryProvider).watchMyJoinRequests(id),
        ),
        incomingFriendRequestsProvider.overrideWith(
          (ref, id) =>
              ref.watch(friendRepositoryProvider).watchIncomingRequests(id),
        ),
        outgoingFriendRequestsProvider.overrideWith(
          (ref, id) =>
              ref.watch(friendRepositoryProvider).watchOutgoingRequests(id),
        ),
        // 練習用の画面では青緑のアイコン色を使わない。
        avatarPaletteProvider.overrideWithValue(practiceAvatarPalette),
        backStackControllerProvider.overrideWith((ref) {
          final controller = BackStackController();
          ref.onDispose(controller.dispose);
          return controller;
        }),
      ],
      child: _PracticeHomeBody(
        focus: widget.focus,
        topPadding: widget.topPadding,
        directMessage: _dmRepository.directMessage,
      ),
    );
  }
}

class _PracticeHomeBody extends ConsumerStatefulWidget {
  const _PracticeHomeBody({
    required this.focus,
    required this.topPadding,
    required this.directMessage,
  });

  final PracticeFocus? focus;
  final double topPadding;
  final DirectMessage directMessage;

  @override
  ConsumerState<_PracticeHomeBody> createState() => _PracticeHomeBodyState();
}

class _PracticeHomeBodyState extends ConsumerState<_PracticeHomeBody> {
  late int _selectedIndex = _initialIndex();

  /// 狭い画面で開いた練習用の会話（`TalksTab`が本物のルートへ出ないよう、練習用の
  /// 画面の中で表示する）。nullなら語らいの一覧。
  ({DirectMessage dm, String roomId, String roomName})? _openChat;

  /// 「語らいを押す」手順から始まるガイドは、最初に別のタブ（身だしなみ）を開いて
  /// おく（最初から語らいが開いていると、押す意味が無いため）。
  @override
  void initState() {
    super.initState();
    _applyFocus(widget.focus);
  }

  @override
  void didUpdateWidget(_PracticeHomeBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focus != widget.focus) _applyFocus(widget.focus);
  }

  /// 初期設定のプレビュー用に、見せる画面へ切り替える（nullなら何もしない）。
  void _applyFocus(PracticeFocus? focus) {
    switch (focus) {
      case null:
        return;
      case PracticeFocus.talksList:
        _selectedIndex = 0;
        _openChat = null;
      case PracticeFocus.chat:
        _selectedIndex = 0;
        _openChat = (
          dm: widget.directMessage,
          roomId: practiceRoomId,
          roomName: '',
        );
    }
  }

  int _initialIndex() {
    final first = ref.read(tutorialControllerProvider)?.script.steps.first;
    return first?.targetId == TutorialTargetIds.navTalk ? 1 : 0;
  }

  static const _icons = [
    Icons.forum_outlined,
    Icons.face_outlined,
    Icons.settings_outlined,
  ];
  static const _iconSizes = [24.0, 28.0, 28.0];

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    // 案内の層の「やめる」ボタン（右上）が、会話上部の右端のボタン（カレンダー等）に
    // 重ならないよう、上に余白を空ける。
    return Padding(
      padding: EdgeInsets.only(top: widget.topPadding),
      child: ChipNavShell(
        icons: _icons,
        iconSizes: _iconSizes,
        labels: [strings.navTalk, strings.navProfile, strings.navSettings],
        selectedIndex: _selectedIndex,
        onSelected: (i) => setState(() => _selectedIndex = i),
        chipWrapper: (index, chip) => switch (index) {
          0 => TutorialTarget(id: TutorialTargetIds.navTalk, child: chip),
          1 => TutorialTarget(id: TutorialTargetIds.navProfile, child: chip),
          _ => chip,
        },
        child: IndexedStack(
          index: _selectedIndex,
          children: [
            _openChat == null
                ? TalksTab(
                    currentUser: practiceUser,
                    onOpenDmFullscreen: (dm, roomId, roomName) => setState(
                      () => _openChat = (
                        dm: dm,
                        roomId: roomId,
                        roomName: roomName,
                      ),
                    ),
                  )
                : DmChatPane(
                    currentUser: practiceUser,
                    dm: _openChat!.dm,
                    roomId: _openChat!.roomId,
                    roomName: _openChat!.roomName,
                    // 通話のボタンを出す（練習中は何も始めない）。
                    onCallPressed: () {},
                    onVideoCallPressed: () {},
                  ),
            const ProfileTab(currentUser: practiceUser),
            const SizedBox.shrink(),
          ],
        ),
      ),
    );
  }
}
