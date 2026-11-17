import 'dart:async';

import 'package:flutter/foundation.dart';

/// 寄合の一覧の1回分の結果（[fromCache]は端末のキャッシュ由来か）。
class RoomsSnapshot<T> {
  const RoomsSnapshot(this.items, {required this.fromCache});

  final List<T> items;
  final bool fromCache;
}

/// 寄合の一覧の購読を、キャッシュの空振りと失敗に強くする（2026-11-17）。
///
/// Androidで、承認した直後の一対の寄合一覧が空のまま止まった（アプリの再起動では直らず、
/// アカウントを切り替えると直った）。Android・iOS・デスクトップはFirestoreのローカル
/// キャッシュを持ち、素の`snapshots()`は最初にキャッシュ由来の0件を流すことがあるため、
/// サーバーの結果が来ない間は画面が空のままになる、という仮説に基づく防御（原因は未確定）。
///
/// - キャッシュ由来の**0件**は、すぐには流さず保留する。サーバー由来が来たら（0件でも）流す。
/// - サーバー由来が[serverWait]以内に来なければ、サーバーへ直接1回取りに行き
///   （[fetchServer]）、取れなければキャッシュの値（0件）を流す（オフラインで止まらない）。
/// - 購読がエラーで終わったら、[retryDelay]後に張り直す。
/// - 各イベントを`[ROOMS]`のログに出す（会話idなどの[tag]だけ。次に起きた時に原因を拾う）。
Stream<List<T>> resilientRooms<T>({
  required String tag,
  required Stream<RoomsSnapshot<T>> Function() open,
  required Future<List<T>> Function() fetchServer,
  Duration serverWait = const Duration(seconds: 4),
  Duration retryDelay = const Duration(seconds: 5),
  void Function(String message)? log,
}) {
  void out(String message) {
    if (log != null) {
      log(message);
    } else {
      debugPrint('[ROOMS] $tag $message');
    }
  }

  late final StreamController<List<T>> controller;
  StreamSubscription<RoomsSnapshot<T>>? sub;
  Timer? waitTimer;
  Timer? retryTimer;
  var closed = false;
  var confirmed = false;

  void emit(List<T> items) {
    if (!closed) controller.add(items);
  }

  void cancelWait() {
    waitTimer?.cancel();
    waitTimer = null;
  }

  void startWait() {
    if (waitTimer != null || confirmed) return;
    waitTimer = Timer(serverWait, () async {
      waitTimer = null;
      if (closed || confirmed) return;
      out('server snapshot did not arrive; fetching from server');
      try {
        final items = await fetchServer();
        if (closed) return;
        confirmed = true;
        out('server fetch ok docs=${items.length}');
        emit(items);
      } catch (e) {
        if (closed) return;
        out('server fetch failed ($e); using cache');
        confirmed = true;
        emit(const []);
      }
    });
  }

  void subscribe() {
    sub = open().listen(
      (snapshot) {
        out('docs=${snapshot.items.length} fromCache=${snapshot.fromCache}');
        if (!snapshot.fromCache) {
          confirmed = true;
          cancelWait();
          emit(snapshot.items);
        } else if (snapshot.items.isNotEmpty) {
          // キャッシュに実データがあれば、それを先に見せる。
          emit(snapshot.items);
        } else if (!confirmed) {
          startWait();
        } else {
          emit(snapshot.items);
        }
      },
      onError: (Object e, StackTrace st) {
        out('error: $e; retrying in ${retryDelay.inSeconds}s');
        sub?.cancel();
        sub = null;
        cancelWait();
        confirmed = false;
        if (closed) return;
        retryTimer = Timer(retryDelay, () {
          if (!closed) subscribe();
        });
      },
    );
  }

  controller = StreamController<List<T>>.broadcast(
    onListen: () {
      closed = false;
      confirmed = false;
      subscribe();
    },
    onCancel: () async {
      closed = true;
      cancelWait();
      retryTimer?.cancel();
      await sub?.cancel();
      sub = null;
    },
  );
  return controller.stream;
}
