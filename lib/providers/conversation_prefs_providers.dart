import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/conversation_prefs.dart';
import 'repository_providers.dart';

/// 自分の一対・広場すべてのピン留め・通知オフ設定（conversationId -> prefs）。
final conversationPrefsProvider =
    StreamProvider.family<Map<String, ConversationPrefs>, String>((ref, userId) {
  return ref.watch(conversationPrefsRepositoryProvider).watchAll(userId);
});
