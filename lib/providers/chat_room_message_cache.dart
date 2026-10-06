import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/message.dart';
import '../models/message_cursor.dart';
import 'repository_providers.dart';

/// メッセージ画面のスクロール位置を「見ていたメッセージ」で覚えるアンカー
/// （2026-10-04追加）。リストはreverse（index 0が最新）のため、離れている間に
/// 新着が来るとindexは別のメッセージを指してしまう。そこでメッセージIDと、
/// そのアイテムの先頭端の位置（`ItemPosition.itemLeadingEdge`）で保持する。
class ChatScrollAnchor {
  const ChatScrollAnchor({required this.messageId, required this.leadingEdge});

  final String messageId;
  final double leadingEdge;
}

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
  /// 最新[kMessagePageSize]件のライブ窓（Firestoreの`limit`付き購読）。
  /// 新着で窓が進むと、押し出された分は[olderMessages]の先頭へ移される
  /// （[_applyLiveWindow]）。
  List<Message> liveTailMessages = const [];

  /// ライブ窓より古い蓄積分（新しい順）。[loadOlder]で読み込んだ過去ページと、
  /// ライブ窓から押し出されたメッセージ。常に[liveTailMessages]のどれよりも
  /// 古く、互いに重複しない（`chat_panes.dart`は単純結合するだけで全体が
  /// 降順になる前提）。
  final List<Message> olderMessages = [];

  /// 次に[loadOlder]で読み始める位置（現在ロード済みの最も古いメッセージ）。
  /// まだ何も無い、または`sentAt`未確定（送信直後）ならnull。
  MessageCursor? get oldestLoadedCursor {
    final oldest = olderMessages.isNotEmpty
        ? olderMessages.last
        : (liveTailMessages.isNotEmpty ? liveTailMessages.last : null);
    final sentAt = oldest?.sentAt;
    if (oldest == null || sentAt == null) return null;
    return MessageCursor(sentAt: sentAt, messageId: oldest.messageId);
  }

  bool _hasReceivedLive = false;

  bool isLoadingOlder = false;
  bool hasMoreHistory = true;

  /// この寄合を最後に離れた時点のスクロール位置（最新側にいた場合はnull）。
  /// `ChatScreen`はPaneの再生成・寄合切替・一覧へのpopで作り直されるため、
  /// Paneより長生きするこのキャッシュに保持して、戻ってきた時に最新へ
  /// ジャンプしないようにする（2026-10-04追加）。
  ChatScrollAnchor? lastScrollAnchor;

  /// 現在この寄合を表示しているWidget Stateの数。0より大きい間は
  /// [ChatRoomMessageCacheManager]のLRU破棄対象にならない。
  int refCount = 0;

  /// refCountが0になった時点の[ChatRoomMessageCacheManager]内の通し番号
  /// （LRU破棄の判定に使う。ウォールクロックの解像度に依存せず厳密な
  /// 順序を保証するため、時刻ではなく単調増加のカウンタを使う）。
  /// 表示中はnull。
  int? idleSequence;

  StreamSubscription<List<Message>>? _tailSub;

  /// 購読が終了・エラーで止まった際の自動再購読の連続失敗回数
  /// （バックオフ計算用。1件でも受信できれば0に戻す）。
  int _retryCount = 0;
  Timer? _retryTimer;

  /// まだ購読していなければ[watchLiveWindow]で購読を開始する（冪等）。
  /// 既に購読済みの場合は何もせず、これまでに蓄積済みの
  /// [liveTailMessages]等をそのまま使わせる。
  ///
  /// 購読が終了・エラーで止まった場合は`_tailSub`を解放し（2026-10-06修正。
  /// 以前は止まった購読が残り続け、寄合に戻っても二度と更新されなかった）、
  /// 表示中（[refCount] > 0）なら間隔を延ばしながら自動で再購読する。
  /// 非表示のままなら、次に表示した際の本メソッド呼び出しで再購読される。
  void ensureSubscribed(Stream<List<Message>> Function() watchLiveWindow) {
    if (_tailSub != null) return;
    _retryTimer?.cancel();
    _retryTimer = null;
    late final StreamSubscription<List<Message>> sub;
    void onStopped(Object? error) {
      if (!identical(_tailSub, sub)) return;
      debugPrint('ChatRoomMessageCacheEntry: 購読が停止しました: $error');
      _tailSub = null;
      if (refCount <= 0) return;
      final delay = Duration(seconds: min(30, 3 * (1 << min(_retryCount, 3))));
      _retryCount++;
      _retryTimer = Timer(delay, () {
        _retryTimer = null;
        if (refCount > 0) ensureSubscribed(watchLiveWindow);
      });
    }

    sub = watchLiveWindow().listen(
      (window) {
        _retryCount = 0;
        _applyLiveWindow(window);
        notifyListeners();
      },
      onError: onStopped,
      onDone: () => onStopped('done'),
      cancelOnError: true,
    );
    _tailSub = sub;
  }

  /// [a]が[pivot]より古い（Firestoreの`sentAt`降順＋`__name__`降順の並びで
  /// 後ろにある）か。`sentAt`未確定（送信直後）は最新扱いで、古いとはみなさない。
  static bool _isOlderThan(Message a, Message pivot) {
    final aSentAt = a.sentAt;
    final pivotSentAt = pivot.sentAt;
    if (aSentAt == null || pivotSentAt == null) return false;
    final byTime = aSentAt.compareTo(pivotSentAt);
    if (byTime != 0) return byTime < 0;
    return a.messageId.compareTo(pivot.messageId) < 0;
  }

  /// 新しいライブ窓[next]を反映し、[olderMessages]との整合を保つ
  /// （2026-10-06追加。日単位だった頃は2つのリストが互いに素な前提で
  /// 重複排除が不要だったが、件数ベースでは窓が新着で進むため必要）。
  /// - 窓が満杯（[kMessagePageSize]件）で、直前の窓と重なりがある場合のみ、
  ///   窓から押し出された分（新しい窓の最古より古いもの）を[olderMessages]の
  ///   先頭へ移す。窓内で物理削除されたものは移さず捨てる。
  /// - 直前の窓と全く重ならない場合（古いキャッシュ表示の後にサーバーの
  ///   最新が届いた等）は、間の欠落を作らないよう[olderMessages]を捨てて
  ///   読み直す。
  /// - 新しい窓に現れたIDは[olderMessages]から除く（窓内の削除で古い
  ///   メッセージが窓へ繰り上がった場合の重複防止）。
  void _applyLiveWindow(List<Message> next) {
    final previous = liveTailMessages;
    final nextIds = {for (final m in next) m.messageId};
    if (previous.isNotEmpty) {
      final overlaps = previous.any((m) => nextIds.contains(m.messageId));
      if (!overlaps && next.isNotEmpty) {
        olderMessages.clear();
        hasMoreHistory = true;
      } else if (next.length >= kMessagePageSize) {
        final pivot = next.last;
        final spilled = [
          for (final m in previous)
            if (!nextIds.contains(m.messageId) && _isOlderThan(m, pivot)) m,
        ];
        olderMessages.removeWhere((m) => nextIds.contains(m.messageId));
        olderMessages.insertAll(0, spilled);
      }
    }
    olderMessages.removeWhere((m) => nextIds.contains(m.messageId));
    liveTailMessages = next;
    _hasReceivedLive = true;
  }

  /// 現在ロード済みの最も古いメッセージより古い1ページ（最大
  /// [kMessagePageSize]件）を[loadOlderPage]で取得して[olderMessages]へ
  /// 追記する。取得件数がページ未満なら、これ以上遡る履歴は無いとみなす。
  Future<void> loadOlder(
    Future<List<Message>> Function(MessageCursor before) loadOlderPage,
  ) async {
    if (isLoadingOlder || !hasMoreHistory) return;
    final cursor = oldestLoadedCursor;
    if (cursor == null) {
      // ライブ窓を受信済みで1件も無い（空の寄合）なら、遡る履歴も無い。
      if (_hasReceivedLive && liveTailMessages.isEmpty) {
        hasMoreHistory = false;
        notifyListeners();
      }
      return;
    }
    isLoadingOlder = true;
    notifyListeners();
    try {
      final page = await loadOlderPage(cursor);
      final known = {
        for (final m in liveTailMessages) m.messageId,
        for (final m in olderMessages) m.messageId,
      };
      olderMessages.addAll(page.where((m) => !known.contains(m.messageId)));
      if (page.length < kMessagePageSize) hasMoreHistory = false;
    } finally {
      isLoadingOlder = false;
      notifyListeners();
    }
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
    _retryTimer?.cancel();
    _retryTimer = null;
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

  /// 表示を開始せず（`refCount`を増やさず）、既存エントリがあれば参照だけ
  /// 覗き見る（2026-09-12追加、語らい検索のメッセージ内容検索
  /// `TalksMessageSearchSession`専用）。無ければ新規エントリを作らずnullを
  /// 返す（[attach]と異なり、検索のためだけに空のFirestore購読を新設したく
  /// ないため）。
  ChatRoomMessageCacheEntry? peek(ChatRoomCacheKey key) => _entries[key];

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
