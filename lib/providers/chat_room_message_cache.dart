import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/day_messages_page.dart';
import '../models/message.dart';
import 'repository_providers.dart';

/// 一対の寄合1つ、または広場の寄合1つを一意に指す不変のキー
/// （2026-09-10追加）。[ChatRoomMessageCacheManager]のMapキーに使う。
@immutable
class ChatRoomCacheKey {
  const ChatRoomCacheKey({
    required this.isDm,
    required this.conversationId,
    required this.roomId,
  });

  final bool isDm;

  /// 一対なら`DirectMessage.dmId`、広場なら`Group.groupId`。
  final String conversationId;
  final String roomId;

  @override
  bool operator ==(Object other) =>
      other is ChatRoomCacheKey &&
      other.isDm == isDm &&
      other.conversationId == conversationId &&
      other.roomId == roomId;

  @override
  int get hashCode => Object.hash(isDm, conversationId, roomId);

  @override
  String toString() =>
      'ChatRoomCacheKey(${isDm ? 'dm' : 'group'}:$conversationId/$roomId)';
}

/// 1つの(会話, 寄合)ペア分のメッセージ購読・読み込み済みリストを、
/// `_DmChatPaneState`/`_GroupChatPaneState`（`chat_panes.dart`）の代わりに
/// 保持するキャッシュエントリ（2026-09-10追加）。
///
/// 以前はこれらのフィールドをState自身が持っていたため、寄合を切り替えて
/// `ChatScreen`のKeyが変わりStateごと破棄・再生成されるたびにFirestore購読も
/// 最初からやり直しになっていた（寄合切り替えのたびにメッセージが一瞬
/// 消えて読み込み直される体感遅延の主因）。このエントリは
/// [ChatRoomMessageCacheManager]がアプリセッション寿命で保持するため、
/// Stateが破棄されても購読は裏で生き続け、同じ寄合に戻った時は
/// 既に読み込み済みのデータへ即座にアタッチできる。
class ChatRoomMessageCacheEntry extends ChangeNotifier {
  /// 直近の活動日1日分のライブ購読分。
  List<Message> liveTailMessages = const [];

  /// [loadOlder]で読み込んだ、直近の活動日より古い日の蓄積分。
  final List<Message> olderMessages = [];

  /// 次に[loadOlder]を呼ぶ際の境界（現在読み込み済みの最も古い日の
  /// 開始時刻）。[ensureSubscribed]の初回応答で確定する。
  DateTime? oldestLoadedDayStart;

  bool isLoadingOlder = false;
  bool hasMoreHistory = true;

  /// 現在この寄合を表示しているWidget Stateの数。0より大きい間は
  /// [ChatRoomMessageCacheManager]のLRU破棄対象にならない。
  int refCount = 0;

  /// refCountが0になった時点の[ChatRoomMessageCacheManager]内の通し番号
  /// （LRU破棄の判定に使う。ウォールクロックの解像度に依存せず厳密な
  /// 順序を保証するため、時刻ではなく単調増加のカウンタを使う）。
  /// 表示中はnull。
  int? idleSequence;

  StreamSubscription<DayMessagesPage>? _tailSub;

  /// まだ購読していなければ[watchLatestDay]で購読を開始する（冪等）。
  /// 既に購読済みの場合は何もせず、これまでに蓄積済みの
  /// [liveTailMessages]等をそのまま使わせる。
  void ensureSubscribed(Stream<DayMessagesPage> Function() watchLatestDay) {
    if (_tailSub != null) return;
    _tailSub = watchLatestDay().listen((page) {
      liveTailMessages = page.messages;
      oldestLoadedDayStart ??= page.dayStart;
      notifyListeners();
    });
  }

  Future<void> loadOlder(
    Future<DayMessagesPage?> Function(DateTime beforeDayStart) loadOlderDay,
  ) async {
    final boundary = oldestLoadedDayStart;
    if (isLoadingOlder || !hasMoreHistory || boundary == null) return;
    isLoadingOlder = true;
    notifyListeners();
    final page = await loadOlderDay(boundary);
    isLoadingOlder = false;
    if (page == null) {
      hasMoreHistory = false;
    } else {
      olderMessages.addAll(page.messages);
      oldestLoadedDayStart = page.dayStart;
    }
    notifyListeners();
  }

  /// 編集・リアクション・既読・削除等のメッセージ変更操作を実行した後、
  /// 対象が過去日（[olderMessages]、静的スナップショット）に含まれていれば
  /// 最新状態を取り直してローカルに反映する。当日分（[liveTailMessages]）は
  /// Firestoreのライブ購読で自動反映されるため何もしない
  /// （`_DmChatPaneState._afterMutation`/`_GroupChatPaneState._afterMutation`
  /// から移植、ロジックは変更なし）。
  Future<void> afterMutation(
    Future<void> Function() action, {
    required List<String> messageIds,
    required Future<Message?> Function(String messageId) fetchMessage,
  }) async {
    await action();
    for (final id in messageIds) {
      if (liveTailMessages.any((m) => m.messageId == id)) continue;
      if (!olderMessages.any((m) => m.messageId == id)) continue;
      final fresh = await fetchMessage(id);
      final index = olderMessages.indexWhere((m) => m.messageId == id);
      if (index == -1) continue;
      if (fresh == null) {
        olderMessages.removeAt(index);
      } else {
        olderMessages[index] = fresh;
      }
      notifyListeners();
    }
  }

  /// Firestore購読を止める（[ChatRoomMessageCacheManager]のLRU破棄、または
  /// 会話自体の削除時にのみ呼ばれる。表示中のStateを持つ`dispose()`からは
  /// 呼ばない — それがこのキャッシュ層の存在意義そのもの）。
  void cancelSubscription() {
    _tailSub?.cancel();
    _tailSub = null;
  }
}

/// [ChatRoomMessageCacheEntry]を(会話, 寄合)キーで管理し、表示されなくなった
/// 寄合の購読もしばらく裏で生かし続けるマネージャ（2026-09-10追加）。
///
/// 「現在表示中のエントリは絶対に破棄しない」を[ChatRoomMessageCacheEntry
/// .refCount]で、「無制限にFirestoreリスナー・メモリを溜め込まない」を
/// [maxIdleEntries]を超えた分からLRU（最も長くrefCount==0のもの）で破棄する
/// ことで両立する。
class ChatRoomMessageCacheManager {
  /// 表示中でなくなった（refCount==0の）エントリを、裏で生かし続ける上限件数。
  /// これを超えた分だけ、最も長く非表示のものからFirestore購読を破棄する。
  static const int maxIdleEntries = 6;

  final _entries = <ChatRoomCacheKey, ChatRoomMessageCacheEntry>{};

  /// [ChatRoomMessageCacheEntry.idleSequence]採番用の単調増加カウンタ。
  int _idleSequenceCounter = 0;

  /// この寄合の表示を開始する。既存エントリがあれば（購読・読み込み済み
  /// データを保ったまま）それを返し、無ければ新規に作る。
  ChatRoomMessageCacheEntry attach(ChatRoomCacheKey key) {
    final entry = _entries.remove(key) ?? ChatRoomMessageCacheEntry();
    // 挿入し直すことでLinkedHashMapの末尾（最新アクセス）に移動する
    // （`talks_tab.dart`の`_visitedConversationKeys`と同じMRU管理）。
    _entries[key] = entry;
    entry.refCount++;
    entry.idleSequence = null;
    return entry;
  }

  /// この寄合の表示を終了する。Firestore購読自体はここでは止めず、
  /// [maxIdleEntries]を超えた場合にのみ古いものから破棄する。
  void detach(ChatRoomCacheKey key, ChatRoomMessageCacheEntry entry) {
    entry.refCount--;
    if (entry.refCount <= 0) {
      entry.refCount = 0;
      entry.idleSequence = _idleSequenceCounter++;
      _evictIfNeeded();
    }
  }

  void _evictIfNeeded() {
    final idle = _entries.entries.where((e) => e.value.refCount <= 0).toList()
      ..sort(
        (a, b) =>
            (a.value.idleSequence ?? 0).compareTo(b.value.idleSequence ?? 0),
      );
    final overflow = idle.length - maxIdleEntries;
    for (var i = 0; i < overflow; i++) {
      final key = idle[i].key;
      _entries.remove(key)?.cancelSubscription();
    }
  }

  /// 会話（一対・広場）自体が削除された時に、その会話に属する全寄合の
  /// エントリを強制的に破棄する（`talks_tab.dart`の
  /// `_visitedConversationKeys.removeWhere`と同じタイミングで呼ぶ）。
  void evictConversation(String conversationId) {
    final keys = _entries.keys
        .where((k) => k.conversationId == conversationId)
        .toList();
    for (final key in keys) {
      _entries.remove(key)?.cancelSubscription();
    }
  }

  /// 全エントリを破棄する（サインアウト時用）。
  void disposeAll() {
    for (final entry in _entries.values) {
      entry.cancelSubscription();
    }
    _entries.clear();
  }
}

/// アプリセッション（サインイン中）を通じて1つだけ生存する
/// [ChatRoomMessageCacheManager]。[authStateProvider]をwatchすることで
/// サインイン/サインアウトのたびに作り直され、旧ユーザーのFirestore購読が
/// 残り続けて`permission-denied`が出る事態を防ぐ
/// （`repository_providers.dart`の`isAdminProvider`と同じパターン）。
final chatRoomMessageCacheManagerProvider =
    Provider<ChatRoomMessageCacheManager>((ref) {
      ref.watch(authStateProvider);
      final manager = ChatRoomMessageCacheManager();
      ref.onDispose(manager.disposeAll);
      return manager;
    });
