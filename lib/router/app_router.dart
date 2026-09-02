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
import '../utils/platform_info.dart';
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
  });
  final AppUser currentUser;
  final DirectMessage dm;
  final String roomId;
  final String roomName;
}

class GroupChatArgs {
  const GroupChatArgs({
    required this.currentUser,
    required this.group,
    required this.roomId,
    required this.roomName,
  });
  final AppUser currentUser;
  final Group group;
  final String roomId;
  final String roomName;
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
  // [alsoSwipeLeft]を指定した画面（メッセージ画面）は左スワイプでも同じく
  // 戻れるようにする。他画面の「右スワイプ＝戻る」という規約はそのまま
  // 維持しつつ、要望のあった左スワイプを追加で許可する形。吹き出し自体が
  // 左スワイプで返信/編集ジェスチャーを持っているため、吹き出しの上からの
  // スワイプではそちらが優先され反応しない場合がある（AppBar・入力欄・
  // 吹き出しの無い余白からのスワイプでは問題なく効く）。
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
        builder: (context, state) {
          final args = state.extra! as DmChatArgs;
          return swipeBack(
            alsoSwipeLeft: true,
            DmChatPane(
              currentUser: args.currentUser,
              dm: args.dm,
              roomId: args.roomId,
              roomName: args.roomName,
              onCallPressed: () => startCall(args.currentUser, args.dm),
              onVideoCallPressed: () =>
                  startCall(args.currentUser, args.dm, isVideo: true),
              showRoomTabBar: true,
              onSwipeBack: () {
                if (router.canPop()) router.pop();
              },
            ),
          );
        },
      ),
      GoRoute(
        path: '/chat/group',
        builder: (context, state) {
          final args = state.extra! as GroupChatArgs;
          return swipeBack(
            alsoSwipeLeft: true,
            GroupChatPane(
              currentUser: args.currentUser,
              group: args.group,
              roomId: args.roomId,
              roomName: args.roomName,
              showRoomTabBar: true,
              onSwipeBack: () {
                if (router.canPop()) router.pop();
              },
            ),
          );
        },
      ),
      GoRoute(
        path: '/announcements',
        builder: (context, state) => swipeBack(
          AnnouncementScreen(
            currentUser: state.extra! as AppUser,
            onSwipeBack: () {
              if (router.canPop()) router.pop();
            },
          ),
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
        builder: (context, state) => AuthGate(
          builder: (context, currentUser) => NotificationChatOpener(
            currentUser: currentUser,
            isDm: true,
            conversationId: state.pathParameters['dmId']!,
            roomId: state.uri.queryParameters['roomId'],
          ),
        ),
      ),
      GoRoute(
        path: '/chat/group/:groupId',
        builder: (context, state) => AuthGate(
          builder: (context, currentUser) => NotificationChatOpener(
            currentUser: currentUser,
            isDm: false,
            conversationId: state.pathParameters['groupId']!,
            roomId: state.uri.queryParameters['roomId'],
          ),
        ),
      ),
    ],
  );

  globalRouter = router;
  return router;
});
