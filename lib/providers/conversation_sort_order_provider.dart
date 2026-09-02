import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/conversation_sort_order.dart';
import 'repository_providers.dart';

const _prefsKey = 'conversationSortOrder';

/// 端末に保存されている初期の語らい一覧並べ替え順。main()で起動前に読み込み、
/// ProviderScopeのoverrideとして渡す。
final initialConversationSortOrderProvider = Provider<ConversationSortOrder>((
  ref,
) {
  throw UnimplementedError('main()でoverrideすること');
});

Future<ConversationSortOrder> loadInitialConversationSortOrder() async {
  final prefs = await SharedPreferences.getInstance();
  return ConversationSortOrder.fromName(prefs.getString(_prefsKey));
}

class ConversationSortOrderNotifier extends Notifier<ConversationSortOrder> {
  @override
  ConversationSortOrder build() =>
      ref.watch(initialConversationSortOrderProvider);

  Future<void> setOrder(ConversationSortOrder order) async {
    state = order;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, order.name);
    final userId = ref.read(authStateProvider).value?.uid;
    if (userId == null) return;
    await ref
        .read(userRepositoryProvider)
        .updateUserPreference(userId, 'conversationSortOrder', order.name);
  }

  /// ログイン時、Firestoreに保存されている値で端末側を上書きする
  /// （既にFirestore側にある値の書き戻しは行わない）。
  Future<void> syncFromRemote(ConversationSortOrder order) async {
    state = order;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, order.name);
  }
}

final conversationSortOrderProvider =
    NotifierProvider<ConversationSortOrderNotifier, ConversationSortOrder>(
      ConversationSortOrderNotifier.new,
    );
