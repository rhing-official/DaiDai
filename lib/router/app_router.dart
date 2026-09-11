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
import '../features/profile/invite_screen.dart';
import '../models/app_user.dart';
import '../models/call.dart';
import '../models/direct_message.dart';
import '../models/group.dart';
import '../providers/repository_providers.dart';
import '../theme/motion.dart';
import '../utils/platform_info.dart';
import '../widgets/interactive_swipe_back.dart';
import '../widgets/swipe_gestures.dart';

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
}

class GroupChatArgs {
  const GroupChatArgs({
    required this.currentUser,
    required this.group,
    required this.roomId,
    required this.roomName,
    this.showRoomTabBar = true,
  });
  final AppUser currentUser;
  final Group group;
  final String roomId;
  final String roomName;

  /// [DmChatArgs.showRoomTabBar]と同じ理由（2026-09-11追加）。
  final bool showRoomTabBar;
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

  // pushで開いた画面向けの「右スワイプで戻る」。通話画面（/call・/group-call）は
  // 誤スワイプでの離脱・切断事故を避けるため対象外にしている。
  // [alsoSwipeLeft]は現在どの呼び出し元からも使われていない（他画面の
  // 「右スワイプ＝戻る」という規約のみ）。
  Widget swipeBack(Widget child, {bool alsoSwipeLeft = false}) =>
      SwipeBackDetector(
        onBack: () {
          if (router.canPop()) router.pop();
        },
        onNext: alsoSwipeLeft
            ? () {
                if (router.canPop()) router.pop();
              }
            : null,
        child: child,
      );

  // PageRoute（既定でopaque: true）は、遷移完了後は背後のルートを
  // ビルド・ペイントしなくなる最適化が働く。インタラクティブな戻る
  // スワイプで背後の画面を実際に見せるには、このopaque最適化自体を
  // 無効化する必要がある（Route自身のAnimationControllerをドラッグで
  // 動かさない限り、Transform.translateで見た目だけ動かしても背後は
  // 描画されないまま。2026-09-07判明、詳細は日記参照）。go_routerの
  // `builder:`（既定でopaque:trueのPageになる）ではなく`pageBuilder:`で
  // `CustomTransitionPage(opaque: false, ...)`を返すことで対応する。
  // 見た目（フェード＋下からのスライド＋拡大の「ポップ」演出）は
  // `PopSlidePageTransitionsBuilder`と同じ`buildPopSlideTransition`を
  // 流用し、変化させない。
  Page<void> opaqueFalsePage(GoRouterState state, Widget child) =>
      CustomTransitionPage<void>(
        key: state.pageKey,
        opaque: false,
        transitionsBuilder: (context, animation, secondaryAnimation, child) =>
            buildPopSlideTransition(animation, child),
        child: child,
      );

  // 語らい画面（/chat/dm・/chat/group）専用の「右スワイプで戻る」。
  // 指の位置にリアルタイムに追従し、途中で離すとキャンセルできる
  // インタラクティブなジェスチャーにする（2026-09-07追加）。左スワイプでの
  // 「戻る」は以前対応していたが誤操作につながるため2026-09-10に廃止した
  // （`InteractiveSwipeBackTransition`参照）。
  Page<void> interactiveChatSwipeBack(GoRouterState state, Widget child) =>
      opaqueFalsePage(
        state,
        InteractiveSwipeBackTransition(
          onBack: () {
            if (router.canPop()) router.pop();
          },
          child: child,
        ),
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
          return interactiveChatSwipeBack(
            state,
            DmChatPane(
              currentUser: args.currentUser,
              dm: args.dm,
              roomId: args.roomId,
              roomName: args.roomName,
              onCallPressed: () => startCall(args.currentUser, args.dm),
              onVideoCallPressed: () =>
                  startCall(args.currentUser, args.dm, isVideo: true),
              showRoomTabBar: args.showRoomTabBar,
            ),
          );
        },
      ),
      GoRoute(
        path: '/chat/group',
        pageBuilder: (context, state) {
          final args = state.extra! as GroupChatArgs;
          return interactiveChatSwipeBack(
            state,
            GroupChatPane(
              currentUser: args.currentUser,
              group: args.group,
              roomId: args.roomId,
              roomName: args.roomName,
              showRoomTabBar: args.showRoomTabBar,
            ),
          );
        },
      ),
      GoRoute(
        path: '/announcements',
        // 便り（公式アカウント）画面もチャット画面と同じ吹き出しUIを使うため、
        // 語らい画面と同じインタラクティブな右スワイプ戻るを適用する。
        pageBuilder: (context, state) => interactiveChatSwipeBack(
          state,
          AnnouncementScreen(currentUser: state.extra! as AppUser),
        ),
      ),
      GoRoute(
        path: '/invite/:rhingId',
        builder: (context, state) =>
            swipeBack(InviteScreen(rhingId: state.pathParameters['rhingId']!)),
      ),
      GoRoute(
        path: '/join/:groupId',
        builder: (context, state) => swipeBack(
          JoinGroupScreen(groupId: state.pathParameters['groupId']!),
        ),
      ),
      GoRoute(
        // 招待リンクのOGPキャッシュ回避用に、末尾へタイムスタンプの
        // 追加パスセグメントを付けたURL（group_invite_dialog.dart参照）。
        // 実際のアプリ内ルーティングとしては`:groupId`のみを使う。
        path: '/join/:groupId/:cacheBust',
        builder: (context, state) => swipeBack(
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
        builder: (context, state) => AuthGate(
          builder: (context, currentUser) =>
              AdminGate(currentUser: currentUser),
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
