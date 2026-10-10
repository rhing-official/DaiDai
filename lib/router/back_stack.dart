import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 戻る・進む履歴を保持するタブ単位のスコープ（2026-10-06追加）。履歴は
/// タブごとに独立しており、あるタブの「戻る」が別のタブの状態を戻すことは
/// ない（タブの切り替え自体は履歴に記録しない）。
enum BackScope { talks, profile, settings, admin }

/// タブごとに保存する履歴件数の上限（2026-10-06、ユーザー指示）。
/// 設定画面からは変更せず、ここで事前に決める。
const kMaxBackHistory = 30;

/// 「戻る」「進む」ボタン（ブラウザ・Androidの戻る・デスクトップのマウスの
/// 戻る/進むボタン）を、アプリ内のローカルな画面状態（ペイン・選択・
/// カテゴリ・ダイアログ）と対応させるための仕組み（2026-10-04追加、
/// 2026-10-06にタブ別の論理履歴へ再設計）。
///
/// アプリの画面切り替えの大半は`setState`のローカル状態でブラウザ履歴に残らず、
/// 戻るボタン1回でアプリの外へ出てしまっていた。ブラウザ履歴は「戻る要求の
/// 入口」としてのみ使い（ホーム表示中は常に1件の透明な「ベース」ルート
/// `/_b/0`を積み、戻る操作で消えたら処理して積み直す）、実際の戻り先は
/// このコントローラ内のタブ別スタックで管理する。履歴の長さの上限はアプリ内
/// のスタックだけに適用する（ブラウザ履歴の件数は制御できないため）。
///
/// 戻る要求（[requestBack]）の優先順位:
/// 1. 開いているダイアログ・ポップアップ（全タブ共通）の最新を閉じる
/// 2. 現在のタブ（[activeScope]）で最後に登録された有効なエントリの`onBack`
/// 3. 何も無ければ何もしない（アプリの外へは出ない）
class BackStackController extends ChangeNotifier {
  /// 最初の透明ルート（ブラウザ履歴の入口）のid。以降は単調増加。
  static const int baseId = 0;

  BackStackController({int? tokenCount})
    : _tokenCount = tokenCount ?? (kIsWeb ? kMaxBackHistory + 1 : 1);

  /// 一度に積む透明ルート（履歴トークン）の数。Webでは、戻っても積み直さずに
  /// 済むよう戻れる回数分を事前に積み、ブラウザの「進む」履歴を残す
  /// （2026-10-07）。ネイティブは進むをマウスボタンで直接処理するので1個。
  final int _tokenCount;

  void Function(int id)? _push;

  /// 現在表示しているタブ。`HomeScreen`が切り替えのたびに設定する。
  BackScope activeScope = BackScope.talks;

  final List<_Entry> _stack = [];
  final Map<int, VoidCallback> _dialogs = {};
  final Map<BackScope, List<VoidCallback>> _redo = {};
  final List<int> _tokens = [];
  final Set<int> _forwardIds = {};
  int _nextTokenId = baseId;
  int _nextId = 1;
  int _nextDialogKey = 1;

  /// ルーターへの実際のpushを結びつける（`goRouterProvider`が呼ぶ）。
  void attach({required void Function(int id) push}) {
    _push = push;
  }

  bool get hasBase => _tokens.isNotEmpty;

  /// ダイアログ・ポップアップ・メニュー・全画面ビューア等が開いているか
  /// （2026-10-10追加）。ホーム画面のチップ帯のなぞり遷移が、これらの背後で
  /// タブを切り替えないための判定。ホームの上には常に透明ルート`/_b/*`が
  /// 積まれていて`ModalRoute.isCurrent`では判定できないため、透明ルートを
  /// 数えないこちらを使う。
  bool get hasOpenOverlay => _dialogs.isNotEmpty;

  /// 指定idの透明ルートが有効か（積んでいる、または戻るで消えてブラウザの
  /// 「進む」で復元されうる）。ルーターの`redirect`が、リロード等で来た無効な
  /// `/_b/*`を弾くのに使う。
  bool isLive(int id) => _tokens.contains(id) || _forwardIds.contains(id);

  /// 現在のタブの有効なエントリ数（テスト・デバッグ用）。
  int depthOf(BackScope scope) =>
      _stack.where((e) => e.scope == null || e.scope == scope).length;

  /// ホームの履歴トークンを積む（残りがあれば何もしない）。積み直しは進む先を
  /// 捨てることになるため、トークンが尽きた時だけ行う。
  void ensureBase() {
    if (_tokens.isNotEmpty) return;
    _forwardIds.clear();
    for (var i = 0; i < _tokenCount; i++) {
      final id = _nextTokenId++;
      _tokens.add(id);
      _push?.call(id);
    }
    _log('tokens pushed: $_tokenCount');
  }

  /// ローカル状態を開いた時に呼ぶ。戻る要求で[onBack]が呼ばれる。[onForward]
  /// を渡すと、そのエントリを戻った後の「進む」でやり直せる。[scope]がnullなら
  /// どのタブからでも戻れる共通エントリ。
  ///
  /// [layer]がtrueのエントリは、カレンダー・ノート・アルバム・通話のように
  /// メッセージ画面の上に重なる「層」（[closeTopLayer]が閉じる対象）。語らいの
  /// 会話・寄合の履歴のような、層ではない履歴エントリと区別する。
  int add(
    VoidCallback onBack, {
    BackScope? scope,
    VoidCallback? onForward,
    bool layer = false,
  }) {
    final id = _nextId++;
    _stack.add(_Entry(id, scope, onBack, onForward, layer));
    _log('add id=$id scope=${scope?.name} depth=${_stack.length}');
    return id;
  }

  /// ローカル状態がアプリ内の操作で閉じた時に呼ぶ。
  void remove(int id) {
    final removed = _stack.length;
    _stack.removeWhere((e) => e.id == id);
    if (_stack.length != removed) {
      _log('remove id=$id depth=${_stack.length}');
    }
  }

  /// ダイアログ・ポップアップ・ボトムシートの登録（履歴は積まず、戻る要求が
  /// 来た時に最優先で閉じられる）。
  int addDialog(VoidCallback close) {
    final key = _nextDialogKey++;
    _dialogs[key] = close;
    return key;
  }

  void removeDialog(int key) => _dialogs.remove(key);

  /// 透明ルート`/_b/{id}`が消えた（戻る操作・ルーターのリセット等）時に
  /// 呼ぶ。[NavigatorObserver]から届く。ブラウザ/Androidの戻るはここへ来て、
  /// 戻る要求として処理した後、[BackBaseGuard]がルートを積み直す。
  void onRouteGone(int id) {
    if (!_tokens.remove(id)) return;
    // 戻るで消えたトークンはブラウザの「進む」で復元されうる。
    _forwardIds.add(id);
    requestBack();
    if (_tokens.isEmpty) notifyListeners();
  }

  /// ブラウザの「進む」で履歴トークン`/_b/{id}`が復元された時に呼ぶ
  /// （[BackStackObserver]から届く）。直前の戻るをやり直す。
  void onBrowserForward(int id) {
    if (!_forwardIds.remove(id)) return;
    _tokens.add(id);
    _log('forward from browser id=$id');
    requestForward();
  }

  /// 開いているダイアログ・ポップアップ・全画面ビューア（画像・動画等、
  /// [BackStackObserver]が検知した命令的ルート）の最新を閉じる。閉じたらtrue。
  /// ブラウザの戻るでgo_routerのルート（`/chat/*`）が消える前に、
  /// `GoRoute.onExit`からも呼ばれる（2026-10-06追加）。
  bool closeTopOverlay() {
    if (_dialogs.isEmpty) return false;
    final key = _dialogs.keys.last;
    final close = _dialogs.remove(key);
    _log('close overlay (${_dialogs.length} left)');
    close?.call();
    return true;
  }

  /// 狭い画面のフルスクリーンのメッセージ画面（`/chat/*`）から戻る前に、上に
  /// 重なっている層を1つだけ閉じる（2026-10-07追加）。①ダイアログ・ポップアップ・
  /// 全画面ビューア（[closeTopOverlay]）、②無ければ、現在のタブで最後に登録
  /// されたエントリが層（カレンダー・ノート・アルバム・通話の[BackEntry.layer]）
  /// ならそれ。最後のエントリが語らいの会話・寄合の履歴（層ではない）の場合は
  /// 触らない（フルスクリーンのチャットを表示中に背後の一覧の選択だけが戻って
  /// しまうのを避ける）。閉じたらtrue＝ルートの遷移（一覧へ戻る）を中止する。
  bool closeTopLayer() {
    if (closeTopOverlay()) return true;
    for (var i = _stack.length - 1; i >= 0; i--) {
      final entry = _stack[i];
      if (entry.scope != null && entry.scope != activeScope) continue;
      if (!entry.layer) {
        _log('closeTopLayer: top entry id=${entry.id} is not a layer');
        return false;
      }
      _stack.removeAt(i);
      _log('closeTopLayer: id=${entry.id} depth=${_stack.length}');
      entry.onBack();
      return true;
    }
    _log('closeTopLayer: nothing open (overlays=${_dialogs.length})');
    return false;
  }

  /// 戻る要求。何かを戻した（閉じた）ならtrue。
  bool requestBack() {
    if (closeTopOverlay()) return true;
    for (var i = _stack.length - 1; i >= 0; i--) {
      final entry = _stack[i];
      if (entry.scope != null && entry.scope != activeScope) continue;
      _stack.removeAt(i);
      _log(
        'back: scope=${activeScope.name} id=${entry.id} depth=${_stack.length}',
      );
      final forward = entry.onForward;
      if (forward != null) {
        final redo = _redo.putIfAbsent(activeScope, () => []);
        redo.add(forward);
        if (redo.length > kMaxBackHistory) redo.removeAt(0);
      }
      entry.onBack();
      return true;
    }
    _log('back: nothing to go back (scope=${activeScope.name})');
    return false;
  }

  /// 進む要求（直前の戻るをやり直す）。やり直せたらtrue。
  bool requestForward() {
    final redo = _redo[activeScope];
    if (redo == null || redo.isEmpty) {
      _log('forward: nothing (scope=${activeScope.name})');
      return false;
    }
    _log('forward: scope=${activeScope.name} left=${redo.length - 1}');
    redo.removeLast()();
    return true;
  }

  /// 新しい操作が記録された時にやり直し分を破棄する（履歴の所有者が呼ぶ）。
  void clearRedo(BackScope scope) => _redo[scope]?.clear();

  void _log(String message) {
    if (kDebugMode) debugPrint('[BACK] $message');
  }
}

class _Entry {
  _Entry(this.id, this.scope, this.onBack, this.onForward, this.layer);

  final bool layer;
  final int id;
  final BackScope? scope;
  final VoidCallback onBack;
  final VoidCallback? onForward;
}

/// 戻る・進むで辿れる値の履歴（カーソル付きのリスト、2026-10-06追加）。
/// 会話・寄合の切り替えやタブ内のカテゴリ移動など、「開いている間だけ」では
/// なく値が移り変わる操作を記録するのに使う。[maxLength]を超えた古い分は
/// 捨てる。
class NavHistory<T> {
  NavHistory({this.maxLength = kMaxBackHistory, T? initial}) {
    if (initial != null) _items.add(initial);
  }

  final int maxLength;
  final List<T> _items = [];
  int _cursor = 0;

  T? get current => _items.isEmpty ? null : _items[_cursor];
  bool get canBack => _cursor > 0;
  bool get canForward => _cursor < _items.length - 1;
  int get length => _items.length;

  /// 新しい値を記録する。現在値と同じなら何もせずfalseを返す。やり直し分
  /// （カーソルより先）は破棄する。
  bool push(T value) {
    if (_items.isNotEmpty && _items[_cursor] == value) return false;
    if (_items.isNotEmpty) _items.removeRange(_cursor + 1, _items.length);
    _items.add(value);
    if (_items.length > maxLength) _items.removeAt(0);
    _cursor = _items.length - 1;
    return true;
  }

  /// 1つ前へ戻り、その値を返す（戻れなければnull）。
  T? back() {
    if (!canBack) return null;
    _cursor--;
    return _items[_cursor];
  }

  /// 1つ先へ進み、その値を返す（進めなければnull）。
  T? forward() {
    if (!canForward) return null;
    _cursor++;
    return _items[_cursor];
  }
}

final backStackControllerProvider = Provider<BackStackController>(
  (ref) => BackStackController(),
);

/// `/_b/{id}`の透明なルート（ブラウザ履歴1件分の置き場）。見た目は何も無く、
/// 背後の画面はそのまま表示され続ける。フォーカスも奪わない（背後の
/// 入力欄が入力できなくならないよう`requestFocus: false`）。
class BackPage extends Page<void> {
  // ignore: prefer_const_constructors_in_immutables
  BackPage({required this.id, super.key}) : super(name: '_b/$id');

  final int id;

  @override
  Route<void> createRoute(BuildContext context) => _BackRoute(this);
}

/// 画面を持たない（バリアも無い）ルート。`PageRouteBuilder`等の`ModalRoute`は
/// 透明でもバリアが背後の画面へのタップを遮るため、`OverlayRoute`で作る。
class _BackRoute extends OverlayRoute<void> {
  _BackRoute(Page<void> page) : super(settings: page, requestFocus: false);

  @override
  Iterable<OverlayEntry> createOverlayEntries() => [
    OverlayEntry(
      builder: (context) => const SizedBox.shrink(),
      opaque: false,
      maintainState: true,
    ),
  ];
}

/// `/_b/{id}`ルートの消滅と、ダイアログ系ルートの出現・消滅を
/// [BackStackController]へ伝える。
class BackStackObserver extends NavigatorObserver {
  BackStackObserver(this.controller);

  final BackStackController controller;
  final Map<Route<dynamic>, int> _dialogKeys = {};

  static int? backIdOf(Route<dynamic> route) {
    final name = route.settings.name;
    if (name == null || !name.startsWith('_b/')) return null;
    return int.tryParse(name.substring(3));
  }

  void _gone(Route<dynamic> route) {
    final id = backIdOf(route);
    if (id != null) {
      // Navigatorの更新中に状態を触らないよう、次のマイクロタスクで処理する。
      scheduleMicrotask(() => controller.onRouteGone(id));
      return;
    }
    final key = _dialogKeys.remove(route);
    if (key != null) controller.removeDialog(key);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    // ダイアログ・ポップアップに加え、命令的に積まれた全画面ルート（画像・動画
    // ビューア等。go_routerのページは`Page`なので対象外）も、戻る要求ではまず
    // これだけを閉じる（2026-10-06追加）。
    final imperative = route.settings is! Page<dynamic>;
    final backId = backIdOf(route);
    if (backId != null) {
      // 自前で積んだトークンは対象外（コントローラが`_forwardIds`にあるidだけ
      // 進む操作として扱う）。
      scheduleMicrotask(() => controller.onBrowserForward(backId));
      return;
    }
    if (backIdOf(route) == null &&
        imperative &&
        (route is PopupRoute || route is PageRoute)) {
      _dialogKeys[route] = controller.addDialog(() {
        if (route.isActive) route.navigator?.removeRoute(route);
      });
    }
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _gone(route);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _gone(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (oldRoute != null) _gone(oldRoute);
  }
}

/// ローカルな画面状態が開いている間（[active]がtrue）だけ、戻る要求で
/// [onBack]が呼ばれるようにするエントリを持つ。[scope]は履歴を持つタブ
/// （nullならどのタブからでも戻れる）。[onForward]を渡すと、戻った後に
/// 「進む」でやり直せる。
class BackEntry extends ConsumerStatefulWidget {
  const BackEntry({
    required this.active,
    required this.onBack,
    required this.child,
    this.scope,
    this.onForward,
    this.layer = false,
    super.key,
  });

  /// メッセージ画面の上に重なる層（カレンダー・ノート・アルバム・通話）か。
  /// `BackStackController.closeTopLayer`が閉じる対象になる。
  final bool layer;
  final bool active;
  final VoidCallback onBack;
  final VoidCallback? onForward;
  final BackScope? scope;
  final Widget child;

  @override
  ConsumerState<BackEntry> createState() => _BackEntryState();
}

class _BackEntryState extends ConsumerState<BackEntry> {
  late final BackStackController _controller = ref.read(
    backStackControllerProvider,
  );
  int? _id;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant BackEntry oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    if (widget.active && _id == null) {
      // build中にコントローラへ触れないよう、フレーム後に積む。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.active && _id == null) {
          _id = _controller.add(
            () {
              // 戻る要求で外されるため、IDは先に手放す。
              _id = null;
              widget.onBack();
            },
            scope: widget.scope,
            onForward: widget.onForward == null
                ? null
                : () => widget.onForward!(),
            layer: widget.layer,
          );
        }
      });
    } else if (!widget.active && _id != null) {
      _release();
    }
  }

  void _release() {
    final id = _id;
    _id = null;
    if (id != null) {
      Future<void>.microtask(() => _controller.remove(id));
    }
  }

  @override
  void dispose() {
    _release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// 画面の「現在位置」（[location]）の移り変わりを自動で履歴（[NavHistory]）に
/// 記録し、戻る・進む要求で過去の位置へ[onRestore]する（2026-10-06追加）。
/// 位置が変わった経路（一覧タップ・タブ内の移動・検索ジャンプ等）を問わず、
/// `build`で導出した位置の変化だけを見るため、操作の箇所を個別に触らずに済む。
/// [location]がnullの間は記録しない（位置がまだ確定していない時用）。
/// 復元の途中経過を新しい操作として記録してやり直し分を消さないよう、復元中は
/// 目標位置に着くまで（最大数フレーム）記録を止める。
class NavHistoryBackEntry<T> extends ConsumerStatefulWidget {
  const NavHistoryBackEntry({
    required this.scope,
    required this.location,
    required this.onRestore,
    required this.child,
    this.layer = false,
    super.key,
  });

  final BackScope scope;
  final T? location;
  final void Function(T location) onRestore;
  final Widget child;

  /// trueなら、この履歴をメッセージ画面の上に重なる「層」として登録する
  /// （`BackStackController.closeTopLayer`が1つ戻す対象になる、2026-10-10追加）。
  /// 狭い画面のフルスクリーンのチャット（`/chat/*`）内の寄合の切り替え履歴用。
  final bool layer;

  @override
  ConsumerState<NavHistoryBackEntry<T>> createState() =>
      _NavHistoryBackEntryState<T>();
}

class _NavHistoryBackEntryState<T>
    extends ConsumerState<NavHistoryBackEntry<T>> {
  late final BackStackController _controller = ref.read(
    backStackControllerProvider,
  );
  final NavHistory<T> _history = NavHistory<T>();
  T? _restoreTarget;
  int _restoreFramesLeft = 0;
  int? _entryId;

  void _scheduleRecord() {
    final location = widget.location;
    if (location == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final target = _restoreTarget;
      if (target != null) {
        if (location == target || --_restoreFramesLeft <= 0) {
          _restoreTarget = null;
        }
        return;
      }
      if (_history.push(location)) _controller.clearRedo(widget.scope);
      _syncEntry();
    });
  }

  /// 戻れる間だけ、戻る要求を受けるエントリをコントローラへ登録しておく。
  void _syncEntry() {
    if (_history.canBack && _entryId == null) {
      _entryId = _controller.add(
        () {
          // 戻る要求で既にコントローラから外されている。
          _entryId = null;
          _go(_history.back());
        },
        scope: widget.scope,
        onForward: () => _go(_history.forward()),
        layer: widget.layer,
      );
    } else if (!_history.canBack && _entryId != null) {
      _controller.remove(_entryId!);
      _entryId = null;
    }
  }

  void _go(T? location) {
    if (location == null) return;
    _restoreTarget = location;
    _restoreFramesLeft = 4;
    widget.onRestore(location);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncEntry();
    });
  }

  @override
  void dispose() {
    final id = _entryId;
    _entryId = null;
    if (id != null) {
      Future<void>.microtask(() => _controller.remove(id));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _scheduleRecord();
    return widget.child;
  }
}

/// ホーム画面に置き、ホームを表示している間は常に「ベース」ルートを積んで
/// おく（ブラウザ/Androidの戻るの入口。これより前＝アプリの外へは戻れなく
/// なる）。
class BackBaseGuard extends ConsumerStatefulWidget {
  const BackBaseGuard({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<BackBaseGuard> createState() => _BackBaseGuardState();
}

class _BackBaseGuardState extends ConsumerState<BackBaseGuard> {
  late final BackStackController _controller = ref.read(
    backStackControllerProvider,
  );

  @override
  void initState() {
    super.initState();
    _controller.addListener(_ensure);
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensure());
  }

  void _ensure() {
    if (!mounted) return;
    // 通知はNavigatorの更新中に届くことがあるため、フレーム後に積み直す。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_controller.hasBase) _controller.ensureBase();
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_ensure);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// マウスの「戻る」「進む」ボタン（サイドボタン）を[BackStackController]へ
/// つなぐ（2026-10-06追加）。デスクトップのネイティブアプリ専用で、Webでは
/// ブラウザ自身が履歴を操作する（二重に処理しないよう何もしない）。Flutter
/// エンジンはWindows・Linuxでこれらのボタンを[kBackMouseButton]/
/// [kForwardMouseButton]へ割り当てる。子のタップ・スクロール・テキスト選択と
/// 競合しないよう、ヒットテストにだけ参加する`Listener`で押下を見るだけにする。
class MouseBackForwardListener extends ConsumerWidget {
  const MouseBackForwardListener({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (kIsWeb) return child;
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        if (event.kind != PointerDeviceKind.mouse) return;
        final controller = ref.read(backStackControllerProvider);
        if (event.buttons & kBackMouseButton != 0) {
          controller.requestBack();
        } else if (event.buttons & kForwardMouseButton != 0) {
          controller.requestForward();
        }
      },
      child: child,
    );
  }
}
