import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/app_gate.dart';
import '../features/call/call_screen.dart';
import '../features/call/group_call_screen.dart';
import '../features/chat/add_chat_screen.dart';
import '../features/chat/chat_panes.dart';
import '../features/chat/create_group_screen.dart';
import '../features/chat/join_group_screen.dart';
import '../features/chat/room_list_screen.dart';
import '../features/profile/invite_screen.dart';
import '../models/app_user.dart';
import '../models/call.dart';
import '../models/direct_message.dart';
import '../models/group.dart';
import '../providers/repository_providers.dart';
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

/// 寄合一覧画面（`/chat/dm-rooms`）用。まだどの寄合を開くか決まっていない
/// 段階なので[DmChatArgs]と違いroomId/roomNameは持たない。
class DmRoomListArgs {
  const DmRoomListArgs({required this.currentUser, required this.dm});
  final AppUser currentUser;
  final DirectMessage dm;
}

/// 寄合一覧画面（`/chat/group-rooms`）用。[GroupChatArgs]と違い
/// roomId/roomNameは持たない。
class GroupRoomListArgs {
  const GroupRoomListArgs({required this.currentUser, required this.group});
  final AppUser currentUser;
  final Group group;
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
    required this.currentUser,
    required this.isVideo,
  });
  final String groupCallId;
  final AppUser currentUser;
  final bool isVideo;
}

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
  Widget swipeBack(Widget child, {bool alsoSwipeLeft = false}) => SwipeBackDetector(
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
    router.push(
      '/call',
      extra: CallArgs(call: call, isCaller: true, currentUserId: currentUser.userId),
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
            ),
          );
        },
      ),
      GoRoute(
        path: '/chat/dm-rooms',
        builder: (context, state) {
          final args = state.extra! as DmRoomListArgs;
          return swipeBack(
            DmRoomListScreen(currentUser: args.currentUser, dm: args.dm),
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
            ),
          );
        },
      ),
      GoRoute(
        path: '/chat/group-rooms',
        builder: (context, state) {
          final args = state.extra! as GroupRoomListArgs;
          return swipeBack(
            GroupRoomListScreen(currentUser: args.currentUser, group: args.group),
          );
        },
      ),
      GoRoute(
        path: '/add-chat',
        builder: (context, state) {
          final currentUser = state.extra! as AppUser;
          return swipeBack(AddChatScreen(currentUser: currentUser));
        },
      ),
      GoRoute(
        path: '/create-group',
        builder: (context, state) {
          final currentUser = state.extra! as AppUser;
          return swipeBack(CreateGroupScreen(currentUser: currentUser));
        },
      ),
      GoRoute(
        path: '/invite/:rhingId',
        builder: (context, state) => swipeBack(
          InviteScreen(rhingId: state.pathParameters['rhingId']!),
        ),
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
            currentUser: args.currentUser,
            isVideo: args.isVideo,
          );
        },
      ),
    ],
  );

  return router;
});
