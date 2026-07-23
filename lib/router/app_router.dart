import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/app_gate.dart';
import '../features/call/call_screen.dart';
import '../features/chat/add_chat_screen.dart';
import '../features/chat/chat_panes.dart';
import '../features/chat/create_group_screen.dart';
import '../features/profile/profile_creator_screen.dart';
import '../models/app_user.dart';
import '../models/call.dart';
import '../models/direct_message.dart';
import '../models/group.dart';
import '../providers/repository_providers.dart';

/// 語らい系の画面遷移をURL付きのブラウザ履歴に載せるためのルーター。
/// これによりブラウザ/マウスの「戻る」「進む」がアプリ内の画面遷移と対応する
/// （素朴なNavigator.pushだけだとWebでは履歴に乗らず、「戻る」でサイトごと
/// 離脱してしまうため導入した）。
///
/// 画面間で受け渡すデータ（DirectMessage・Groupなど）はURLに載せず、
/// go_routerの`extra`で渡す。そのためブラウザの直接URL入力や
/// リロードからの復元は現状未対応（フェーズ1のスコープ外）。
class DmChatArgs {
  const DmChatArgs({required this.currentUser, required this.dm});
  final AppUser currentUser;
  final DirectMessage dm;
}

class GroupChatArgs {
  const GroupChatArgs({required this.currentUser, required this.group});
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

final goRouterProvider = Provider<GoRouter>((ref) {
  late final GoRouter router;

  Future<void> startCall(AppUser currentUser, DirectMessage dm) async {
    final callRepository = ref.read(callRepositoryProvider);
    final other = AppUser(
      userId: dm.otherUserId(currentUser.userId),
      rhingId: dm.otherRhingId(currentUser.userId),
    );
    final call = await callRepository.createCall(
      caller: currentUser,
      callee: other,
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
          return DmChatPane(
            currentUser: args.currentUser,
            dm: args.dm,
            onCallPressed: () => startCall(args.currentUser, args.dm),
          );
        },
      ),
      GoRoute(
        path: '/chat/group',
        builder: (context, state) {
          final args = state.extra! as GroupChatArgs;
          return GroupChatPane(currentUser: args.currentUser, group: args.group);
        },
      ),
      GoRoute(
        path: '/add-chat',
        builder: (context, state) {
          final currentUser = state.extra! as AppUser;
          return AddChatScreen(currentUser: currentUser);
        },
      ),
      GoRoute(
        path: '/create-group',
        builder: (context, state) {
          final currentUser = state.extra! as AppUser;
          return CreateGroupScreen(currentUser: currentUser);
        },
      ),
      GoRoute(
        path: '/profile-creator',
        builder: (context, state) {
          final currentUser = state.extra! as AppUser;
          return ProfileCreatorScreen(currentUser: currentUser);
        },
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
    ],
  );

  return router;
});
