import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/app_gate.dart';
import '../features/call/call_screen.dart';
import '../features/chat/add_chat_screen.dart';
import '../features/chat/chat_screen.dart';
import '../features/chat/create_group_screen.dart';
import '../models/app_user.dart';
import '../models/call.dart';
import '../models/direct_message.dart';
import '../models/group.dart';
import '../providers/repository_providers.dart';
import '../providers/user_providers.dart';

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
          final dmRepository = ref.read(directMessageRepositoryProvider);
          final otherUserId = args.dm.otherUserId(args.currentUser.userId);
          final fallbackTitle = '@${args.dm.otherRhingId(args.currentUser.userId)}';
          return Consumer(
            builder: (context, ref, _) {
              final otherUser = ref.watch(watchedUserProvider(otherUserId));
              final nickname = otherUser.maybeWhen(
                data: (user) => user?.activeNickname?.text,
                orElse: () => null,
              );
              return ChatScreen(
                title: (nickname?.isNotEmpty ?? false) ? nickname! : fallbackTitle,
                currentUserId: args.currentUser.userId,
                messagesStream: dmRepository.watchMessages(args.dm.dmId),
                onSend: (content) => dmRepository.sendTextMessage(
                  dmId: args.dm.dmId,
                  senderId: args.currentUser.userId,
                  senderRhingId: args.currentUser.rhingId,
                  content: content,
                ),
                onCallPressed: () => startCall(args.currentUser, args.dm),
              );
            },
          );
        },
      ),
      GoRoute(
        path: '/chat/group',
        builder: (context, state) {
          final args = state.extra! as GroupChatArgs;
          final groupRepository = ref.read(groupRepositoryProvider);
          return ChatScreen(
            title: args.group.name,
            currentUserId: args.currentUser.userId,
            showSenderAvatar: true,
            messagesStream: groupRepository.watchRoomMessages(
              args.group.groupId,
              args.group.defaultRoomId,
            ),
            onSend: (content) => groupRepository.sendRoomMessage(
              groupId: args.group.groupId,
              roomId: args.group.defaultRoomId,
              senderId: args.currentUser.userId,
              senderRhingId: args.currentUser.rhingId,
              content: content,
            ),
          );
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
