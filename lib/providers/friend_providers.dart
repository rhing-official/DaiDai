import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/friend_request.dart';
import 'repository_providers.dart';

/// 自分宛の返答待ち友達申請一覧（一対リスト最上部に表示する）。
final incomingFriendRequestsProvider =
    StreamProvider.family<List<FriendRequest>, String>((ref, userId) {
      return ref.watch(friendRepositoryProvider).watchIncomingRequests(userId);
    });

/// 自分が送った返答待ち友達申請一覧（一対リスト最上部に表示する）。
final outgoingFriendRequestsProvider =
    StreamProvider.family<List<FriendRequest>, String>((ref, userId) {
      return ref.watch(friendRepositoryProvider).watchOutgoingRequests(userId);
    });
