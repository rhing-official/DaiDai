import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/admin/admin_gate.dart';
import '../features/app_gate.dart';
import '../features/auth/auth_gate.dart';
import '../features/call/active_call_session.dart';
import '../features/call/call_screen.dart';
import '../features/call/group_call_screen.dart';
import '../features/chat/announcement_screen.dart';
import '../features/chat/chat_panes.dart';
import '../features/chat/join_group_screen.dart';
import '../features/chat/notification_chat_opener.dart';
import '../features/chat/talks_search_screen.dart';
import '../features/profile/invite_screen.dart';
import '../models/app_user.dart';
import '../models/call.dart';
import '../models/direct_message.dart';
import '../models/group.dart';
import '../providers/repository_providers.dart';
import '../theme/motion.dart';
import '../utils/platform_info.dart';
import '../widgets/interactive_swipe_back.dart';

/// 語らい系の画面遷移をURL付きのブラウザ履歴に載せるためのルーター。
/// これによりブラウザ/マウスの「戻る」「進む」がアプリ内の画面遷移と対応する
/// （素朴なNavigator.pushだけだとWebでは履歴に乗らず、「戻る」でサイトごと
/// 離脱してしまうため導入した）。
///
/// 画面間で受け渡すデータ（DirectMessage・Groupなど）はURLに載せず、
/// go_routerの`extra`で渡す。そのためブラウザの直接URL入力や
/// リロードからの復元は現状未対応（フェーズ1のスコープ外）。
class DmChatArgs {
  const DmChatArgs({
    required this.currentUser,
    required this.dm,
    required this.roomId,
    required this.roomName,
    this.showRoomTabBar = true,
    this.enterFromRight = false,
  });
  final AppUser currentUser;
  final DirectMessage dm;
  final String roomId;
  final String roomName;

  /// AppBar直下に寄合の横スクロールタブバー（`RoomTabBar`）を表示するか
  /// （2026-09-11追加）。縦表示のアイコン＋寄合一覧レイアウト
  /// （`TalksListLayoutStyle.iconSplit`）の寄合一覧から遷移してきた場合は、
  /// 既にそちらで寄合を選んで来ているためfalseにして重複表示を避ける
  /// （`talks_tab.dart`の`_DmDetailWithRooms.openRoomFullscreen`参照）。
  final bool showRoomTabBar;

  /// trueなら入場アニメーションを画面右外からのスライドイン（既定の
  /// `slideDetailPage`の演出）にする（2026-09-11追加、2026-09-12に
  /// 語らい一覧からの通常遷移にも適用範囲を拡大）。右スワイプで戻る動き
  /// （`InteractiveSwipeBackTransition`）と対称に見えるようにするため
  /// （`talks_tab.dart`の`_openDirectMessage`/`openRoomFullscreen`参照）。
  /// falseなら旧来の`buildPopSlideTransition`（フェード＋下からのポップ
  /// 演出）のまま（部屋作成直後の自動遷移等、一覧からの遷移ではない経路が
  /// 引き続き使う）。
  final bool enterFromRight;
}

class GroupChatArgs {
  const GroupChatArgs({
    required this.currentUser,
    required this.group,
    required this.roomId,
    required this.roomName,
    this.showRoomTabBar = true,
    this.enterFromRight = false,
  });
  final AppUser currentUser;
  final Group group;
  final String roomId;
  final String roomName;

  /// [DmChatArgs.showRoomTabBar]と同じ理由（2026-09-11追加）。
  final bool showRoomTabBar;

  /// [DmChatArgs.enterFromRight]と同じ理由（2026-09-11追加）。
  final bool enterFromRight;
}

class CallArgs {
  const CallArgs({
    required this.call,
    required this.isCaller,
    required this.currentUserId,
  });
  final Call call;
  final bool isCaller;
  final String currentUserId;
}

class GroupCallArgs {
  const GroupCallArgs({
    required this.groupCallId,
    required this.groupId,
    required this.currentUser,
    required this.isVideo,
  });
  final String groupCallId;
  final String groupId;
  final AppUser currentUser;
  final bool isVideo;
}

/// [goRouterProvider]が構築した`GoRouter`インスタンスへの参照。Riverpodの
/// `ref`を持たない場所（`push_notifications.dart`の通知タップハンドラ等）
/// から画面遷移するために使う（2026-09-02追加）。Providerは遅延初期化だが、
/// `MaterialApp.router`が起動時に`goRouterProvider`を読むため、通知タップが
/// 起こり得るタイミングには必ず埋まっている。
GoRouter? globalRouter;

final goRouterProvider = Provider<GoRouter>((ref) {
  late final GoRouter router;

  // PageRoute（既定でopaque: true）は、遷移完了後は背後のルートを
  // ビルド・ペイントしなくなる最適化が働く。インタラクティブな戻る
  // スワイプで背後の画面を実際に見せるには、このopaque最適化自体を
  // 無効化する必要がある（Route自身のAnimationControllerをドラッグで
  // 動かさない限り、Transform.translateで見た目だけ動かしても背後は
  // 描画されないまま。2026-09-07判明、詳細は日記参照）。go_routerの
  // `builder:`（既定でopaque:trueのPageになる）ではなく`pageBuilder:`で
  // `CustomTransitionPage(opaque: false, ...)`を返すことで対応する。
  // 入場アニメーションは[transition]で選べ、既定は画面右外からの
  // スライドイン（`buildSlideInFromRightTransition`）。
  Page<void> opaqueFalsePage(
    GoRouterState state,
    Widget child, {
    Widget Function(Animation<double>, Widget) transition =
        buildSlideInFromRightTransition,
  }) => CustomTransitionPage<void>(
    key: state.pageKey,
    opaque: false,
    transitionsBuilder: (context, animation, secondaryAnimation, child) =>
        transition(animation, child),
    child: child,
  );

  // pushで開く画面向けの共通ヘルパー（旧`interactiveChatSwipeBack`/
  // `slideInChatFromRight`/`swipeBack`を統合、2026-09-12）。右スワイプでの
  // インタラクティブな「戻る」（`InteractiveSwipeBackTransition`、指の位置に
  // リアルタイムに追従し途中で離すとキャンセルできるジェスチャー。左スワイプ
  // での「戻る」は誤操作につながるため2026-09-10に廃止済み）を必ず適用し、
  // 入場アニメーションのみ[transition]で選べる。通話画面（/call・
  // /group-call）は誤スワイプでの離脱・切断事故を避けるため対象外にしている。
  Page<void> slideDetailPage(
    GoRouterState state,
    Widget child, {
    Widget Function(Animation<double>, Widget) transition =
        buildSlideInFromRightTransition,
  }) => opaqueFalsePage(
    state,
    InteractiveSwipeBackTransition(
      onBack: () {
        if (router.canPop()) router.pop();
      },
      child: child,
    ),
    transition: transition,
  );

  // 発信側は、モバイルのみ全画面の/callへpushする。PCでは全画面ルートを
  // 使わず、通話セッションを直接開始するだけにする（2026-08-19変更）。
  // 発信者は既にその会話のメッセージ画面を見ているため、以後は
  // `EmbeddedCallPane`がそのメッセージ画面内に埋め込み表示として引き継ぐ。
  Future<void> startCall(
    AppUser currentUser,
    DirectMessage dm, {
    bool isVideo = false,
  }) async {
    final callRepository = ref.read(callRepositoryProvider);
    final other = AppUser(
      userId: dm.otherUserId(currentUser.userId),
      rhingId: dm.otherRhingId(currentUser.userId),
    );
    final call = await callRepository.createCall(
      caller: currentUser,
      callee: other,
      dmId: dm.dmId,
      isVideo: isVideo,
    );
    if (isMobileCallPlatform) {
      router.push(
        '/call',
        extra: CallArgs(
          call: call,
          isCaller: true,
          currentUserId: currentUser.userId,
        ),
      );
      return;
    }
    ref
        .read(activeCallSessionProvider.notifier)
        .startOneToOne(
          call: call,
          isCaller: true,
          callRepository: callRepository,
          directMessageRepository: ref.read(directMessageRepositoryProvider),
        );
  }

  router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (context, state) => const AppGate()),
      GoRoute(
        path: '/chat/dm',
        pageBuilder: (context, state) {
          final args = state.extra! as DmChatArgs;
          final pane = DmChatPane(
            currentUser: args.currentUser,
            dm: args.dm,
            roomId: args.roomId,
            roomName: args.roomName,
            onCallPressed: () => startCall(args.currentUser, args.dm),
            onVideoCallPressed: () =>
                startCall(args.currentUser, args.dm, isVideo: true),
            showRoomTabBar: args.showRoomTabBar,
          );
          return args.enterFromRight
              ? slideDetailPage(state, pane)
              : slideDetailPage(
                  state,
                  pane,
                  transition: buildPopSlideTransition,
                );
        },
      ),
      GoRoute(
        path: '/chat/group',
        pageBuilder: (context, state) {
          final args = state.extra! as GroupChatArgs;
          final pane = GroupChatPane(
            currentUser: args.currentUser,
            group: args.group,
            roomId: args.roomId,
            roomName: args.roomName,
            showRoomTabBar: args.showRoomTabBar,
          );
          return args.enterFromRight
              ? slideDetailPage(state, pane)
              : slideDetailPage(
                  state,
                  pane,
                  transition: buildPopSlideTransition,
                );
        },
      ),
      GoRoute(
        path: '/announcements',
        // 便り（公式アカウント）画面もチャット画面と同じ吹き出しUIを使うため、
        // 語らい画面と同じインタラクティブな右スワイプ戻るを適用する
        // （入場は元々のポップ演出のまま維持）。
        pageBuilder: (context, state) => slideDetailPage(
          state,
          AnnouncementScreen(currentUser: state.extra! as AppUser),
          transition: buildPopSlideTransition,
        ),
      ),
      GoRoute(
        // モバイル実機＋アイコン＋寄合一覧レイアウト（`TalksListLayoutStyle
        // .iconSplit`）専用の語らい検索フルページ（2026-09-12追加）。112px幅の
        // アイコン列内ではインラインの検索結果表示が窮屈なための別ページ化。
        // それ以外（標準レイアウト・コンピューター全般）は`talks_tab.dart`の
        // インライン検索のまま（`TalksSearchScreen`のdocコメント参照）。
        path: '/talks/search',
        pageBuilder: (context, state) => slideDetailPage(
          state,
          TalksSearchScreen(currentUser: state.extra! as AppUser),
        ),
      ),
      GoRoute(
        path: '/invite/:rhingId',
        pageBuilder: (context, state) => slideDetailPage(
          state,
          InviteScreen(rhingId: state.pathParameters['rhingId']!),
        ),
      ),
      GoRoute(
        path: '/join/:groupId',
        pageBuilder: (context, state) => slideDetailPage(
          state,
          JoinGroupScreen(groupId: state.pathParameters['groupId']!),
        ),
      ),
      GoRoute(
        // 招待リンクのOGPキャッシュ回避用に、末尾へタイムスタンプの
        // 追加パスセグメントを付けたURL（group_invite_dialog.dart参照）。
        // 実際のアプリ内ルーティングとしては`:groupId`のみを使う。
        path: '/join/:groupId/:cacheBust',
        pageBuilder: (context, state) => slideDetailPage(
          state,
          JoinGroupScreen(groupId: state.pathParameters['groupId']!),
        ),
      ),
      GoRoute(
        path: '/call',
        builder: (context, state) {
          final args = state.extra! as CallArgs;
          return CallScreen(
            call: args.call,
            isCaller: args.isCaller,
            currentUserId: args.currentUserId,
          );
        },
      ),
      GoRoute(
        path: '/group-call',
        builder: (context, state) {
          final args = state.extra! as GroupCallArgs;
          return GroupCallScreen(
            groupCallId: args.groupCallId,
            groupId: args.groupId,
            currentUser: args.currentUser,
            isVideo: args.isVideo,
          );
        },
      ),
      GoRoute(
        // 運営向け管理画面（隠しルート、2026-08-12新設）。通常のナビゲーション
        // からは導線を出さず、URLを直接開いた場合のみ到達する。AuthGateで
        // 通常のDaiDaiサインインを要求した上で、AdminGateが管理者クレームを
        // 確認する（未サインインでは管理者判定に届かせない）。
        path: '/admin',
        pageBuilder: (context, state) => slideDetailPage(
          state,
          AuthGate(
            builder: (context, currentUser) =>
                AdminGate(currentUser: currentUser),
          ),
        ),
      ),
      GoRoute(
        // プッシュ通知タップ用のディープリンク（2026-09-02追加）。既存の
        // `/chat/dm`（extraベース）とは別ルート。IDのみから会話を復元する
        // 詳細は`NotificationChatOpener`参照。
        path: '/chat/dm/:dmId',
        // NotificationChatOpenerが内部で既にInteractiveSwipeBackTransitionを
        // 組み込み済みのため、ここではopaque:falseのPage化のみ行う。
        pageBuilder: (context, state) => opaqueFalsePage(
          state,
          AuthGate(
            builder: (context, currentUser) => NotificationChatOpener(
              currentUser: currentUser,
              isDm: true,
              conversationId: state.pathParameters['dmId']!,
              roomId: state.uri.queryParameters['roomId'],
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/chat/group/:groupId',
        pageBuilder: (context, state) => opaqueFalsePage(
          state,
          AuthGate(
            builder: (context, currentUser) => NotificationChatOpener(
              currentUser: currentUser,
              isDm: false,
              conversationId: state.pathParameters['groupId']!,
              roomId: state.uri.queryParameters['roomId'],
            ),
          ),
        ),
      ),
    ],
  );

  globalRouter = router;
  return router;
});
