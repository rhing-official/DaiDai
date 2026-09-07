import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../utils/fullscreen/fullscreen.dart';
import 'swipe_gestures.dart' show PinchPriorityPageView;
import 'video_thumbnail.dart';

/// [MediaViewerScreen]で表示する画像・動画1件分（2026-09-07追加、
/// `chat_screen.dart`の`_MediaViewerScreen`から`Message`依存を取り除いて
/// 切り出した共有ウィジェット）。メッセージの添付ファイルにも投票の選択肢
/// 添付にも使えるよう、表示に必要な最小限の3フィールドのみを持つ。
/// [contentType]は'image'|'video'。
class MediaViewerItem {
  const MediaViewerItem({
    required this.id,
    required this.url,
    required this.contentType,
  });

  final String id;
  final String url;
  final String contentType;
}

/// [MediaViewerScreen]を開く（2026-09-07追加）。動画再生非対応環境
/// （Linux/Windows、[videoPlaybackSupported]参照）で対象が動画の場合は
/// ビューアを開かず`launchUrl`で外部アプリに委譲する（以前
/// `chat_screen.dart`の添付タップハンドラと`media_fullscreen_viewer.dart`の
/// `showMediaFullscreenViewer`にそれぞれ個別実装されていた同一ロジックを
/// ここに統一した）。
Future<void> openMediaViewer(
  BuildContext context, {
  required List<MediaViewerItem> items,
  required int initialIndex,
}) {
  final target = items[initialIndex.clamp(0, items.length - 1)];
  if (target.contentType == 'video' && !videoPlaybackSupported) {
    return launchUrl(
      Uri.parse(target.url),
      mode: LaunchMode.externalApplication,
    );
  }
  return Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) =>
          MediaViewerScreen(items: items, initialIndex: initialIndex),
    ),
  );
}

/// 画像・動画の全画面ビューア（2026-08-10追加、2026-08-14に前後スワイプ・
/// 矢印キーでのナビゲーション対応に伴い統合、2026-09-07に`chat_screen.dart`
/// から`lib/widgets/`へ切り出して公開ウィジェット化。投票の選択肢添付
/// 画像・動画にもメッセージ画面の添付画像・動画と全く同じ挙動を持たせる
/// ため、`Message`ではなく軽量な[MediaViewerItem]のリストを受け取る形に
/// した）。[items]を`PageView`でめくる。右スワイプ（＝`PageView`の前ページ
/// 方向）で前、左スワイプで後に切り替わる。コンピューターでは矢印キーでも
/// 同様に操作できる。動画は、最初に開いた対象（[initialIndex]）のときだけ
/// 自動再生し、スワイプ/矢印キーで切り替えた先の動画は自動再生せず、中央の
/// 再生ボタンをタップして再生を始める（[_VideoViewerPage]参照）。ページを
/// 離れた動画は自動的に一時停止するため、一度再生した動画のページへ
/// スワイプ/矢印キーで戻ってきても自動再生されたままにはならず、常に
/// 一時停止から始まる。
class MediaViewerScreen extends StatefulWidget {
  const MediaViewerScreen({
    required this.items,
    required this.initialIndex,
    super.key,
  });

  final List<MediaViewerItem> items;
  final int initialIndex;

  @override
  State<MediaViewerScreen> createState() => _MediaViewerScreenState();
}

class _MediaViewerScreenState extends State<MediaViewerScreen> {
  late final int _safeInitialIndex = widget.initialIndex.clamp(
    0,
    widget.items.length - 1,
  );
  late final PageController _pageController = PageController(
    initialPage: _safeInitialIndex,
  );
  late int _currentIndex = _safeInitialIndex;

  // 動画ページの`GlobalKey`（アイテムid基準）。スペースキーで現在表示中の
  // 動画の再生/一時停止をトグルするために、`_VideoViewerPageState`へ
  // 直接アクセスする（2026-08-14追加）。`PageView.builder`のindexではなく
  // アイテムidをキーにするのは、ウィジェット自身の`key:`としても兼用し、
  // スワイプ中の内部再構築でも同じ`_VideoViewerPageState`（＝
  // `VideoPlayerController`）が保たれるようにするため（GlobalKeyはツリー内
  // での位置に関わらず同一のStateを保持し続ける）。同じ理由で、ページを
  // 離れる動画を`onPageChanged`から一時停止する際にもこのマップ経由で
  // アクセスする（2026-09-06追加、GlobalKeyでStateが保持され続ける副作用で
  // 「一度再生した動画」だけ戻ってきた時に再生中のまま＝自動再生された
  // ように見えてしまう不具合の修正）。
  final Map<String, GlobalKey<_VideoViewerPageState>> _videoPageKeys = {};

  static const _pageChangeDuration = Duration(milliseconds: 200);

  // マウスホイール/トラックパッドでの下スクロール終了のデバウンス用
  // タイマー（2026-08-19追加、下記onPointerSignal参照）。
  Timer? _scrollDismissTimer;

  // Esc/Space等のキーボード操作を受け取る`Focus`用に明示的に持つ
  // `FocusNode`（2026-09-05追加）。以前は`autofocus: true`のみに任せて
  // 暗黙生成のFocusNodeを使っていたが、シークバーの`Slider`や中央ボタンの
  // `InkWell`など子孫のフォーカス可能なウィジェットをタップすると
  // フォーカスがそちらへ移ったまま戻らず、以後Esc/Spaceキーが反応しなく
  // なる不具合があった。以下の`onPointerDown`で毎回このノードへ
  // フォーカスを戻すことで解消する。
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _scrollDismissTimer?.cancel();
    _pageController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// `f`キーでのブラウザ本来の全画面表示トグル（[fullscreen.dart]参照、
  /// 2026-08-18追加）。Web以外ではstub実装が何もしないため無害。
  Future<void> _toggleFullscreen() async {
    if (isDocumentFullscreen) {
      await exitDocumentFullscreen();
    } else {
      await requestDocumentFullscreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        // メッセージ画面へ戻るボタン（2026-08-14、明示化）。
        // `AppBar`の自動`leading`（`automaticallyImplyLeading`）に任せず
        // 明示的に`Navigator.pop`を指定する。
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      // Escキー・矢印キー（コンピューター向け前後ナビゲーション、
      // 2026-08-14追加）・スペースキー（現在表示中の動画の再生/一時停止、
      // 2026-08-14追加）・下スワイプで一覧画面へ戻れるようにする
      // （Escキー・下スワイプは2026-08-11から踏襲）。
      body: Focus(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          if (event.logicalKey == LogicalKeyboardKey.escape) {
            Navigator.of(context).pop();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            _pageController.previousPage(
              duration: _pageChangeDuration,
              curve: Curves.easeInOut,
            );
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
            _pageController.nextPage(
              duration: _pageChangeDuration,
              curve: Curves.easeInOut,
            );
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.space) {
            final currentItemId = widget.items[_currentIndex].id;
            _videoPageKeys[currentItemId]?.currentState?._togglePlayback();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.keyF) {
            _toggleFullscreen();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        // マウスホイール/トラックパッドで上方向へスクロールしただけで
        // 閉じられるようにする（2026-08-19追加、ドラッグ操作は不要。
        // 同日、PCのみ方向をユーザー指示で反転）。モバイルのフリックに
        // よる`SwipeDownToDismiss`はそのまま維持し、その外側にスクロール
        // 検出用の`Listener`を重ねるだけに留める。
        child: Listener(
          // 配下のどこをクリック/タップしても（シークバーのドラッグ開始・
          // 中央ボタン・動画本体タップ含め）ダウン時点で必ずこのノードへ
          // フォーカスを戻す（2026-09-05追加、上記`_focusNode`のdoc参照）。
          onPointerDown: (_) => _focusNode.requestFocus(),
          onPointerSignal: (event) {
            if (event is PointerScrollEvent && event.scrollDelta.dy < -2.0) {
              // トラックパッドの2本指スワイプ等は1回の操作で多数の
              // PointerScrollEventが連続して届く。即座にpop()すると、
              // 同じジェスチャーの残りのイベントがpop後の最前面ルート
              // （メッセージ画面）へ漏れて、その分だけ意図せず
              // スクロールされてしまう不具合があった（2026-08-19判明）。
              // 新しいスクロールイベントが来るたびタイマーを延長し、
              // 一定時間（150ms）イベントが来なくなってからpop()する
              // ことで、ジェスチャー全体をこのListenerが確実に消費
              // しきってから閉じるようにする。
              _scrollDismissTimer?.cancel();
              _scrollDismissTimer = Timer(
                const Duration(milliseconds: 150),
                () {
                  if (mounted) Navigator.of(context).pop();
                },
              );
            }
          },
          child: PinchPriorityPageView(
            controller: _pageController,
            onDismiss: () => Navigator.of(context).pop(),
            itemCount: widget.items.length,
            onPageChanged: (index) {
              // 離れる動画は一時停止する（2026-09-06追加）。GlobalKeyで
              // Stateを保持し続けているため、これをしないと「一度再生した
              // 動画」だけ戻ってきた時に再生中のまま＝自動再生されたように
              // 見えてしまう（上記`_videoPageKeys`のdoc参照）。
              final previousItem = widget.items[_currentIndex];
              if (previousItem.contentType == 'video') {
                _videoPageKeys[previousItem.id]?.currentState?._pause();
              }
              setState(() => _currentIndex = index);
            },
            itemBuilder: (context, index) {
              final item = widget.items[index];
              if (item.contentType == 'video') {
                return _VideoViewerPage(
                  key: _videoPageKeys.putIfAbsent(
                    item.id,
                    GlobalKey<_VideoViewerPageState>.new,
                  ),
                  url: item.url,
                  autoPlay: index == _safeInitialIndex,
                );
              }
              return _ImageViewerPage(url: item.url);
            },
          ),
        ),
      ),
    );
  }
}

/// [MediaViewerScreen]の1ページ分（画像）。Escキー・下スワイプ・画面全体の
/// `Scaffold`/`AppBar`は[MediaViewerScreen]側が共通で持つため、ここでは
/// 画像本体と「画像以外の箇所のタップで閉じる」ジェスチャーのみを持つ
/// （2026-08-10追加、2026-08-14に[MediaViewerScreen]への統合に伴い
/// `_ImageViewerScreen`から改名）。内側のGestureDetectorは何もしないonTapで
/// タップを吸収し、画像自体をタップした際に外側へ伝播して閉じてしまうのを
/// 防ぐ。画像をズームしてパン中はInteractiveViewer側のジェスチャーが
/// 優先されるため誤って閉じない。
class _ImageViewerPage extends StatelessWidget {
  const _ImageViewerPage({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).pop(),
      child: GestureDetector(
        onTap: () {},
        child: SizedBox.expand(
          child: InteractiveViewer(
            child: Image.network(url, fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }
}

/// [MediaViewerScreen]の1ページ分（動画）。Escキー・下スワイプ・画面全体の
/// `Scaffold`/`AppBar`は[MediaViewerScreen]側が共通で持つため、ここでは
/// 動画本体・再生コントロールのみを持つ（2026-08-11追加、2026-08-14に
/// [MediaViewerScreen]への統合に伴い`_VideoViewerScreen`から改名）。
/// `video_player`はiOS/Android/Web/macOSのみ対応のため、Linux/Windowsでは
/// この画面を開かず外部アプリで開く（呼び出し元の[openMediaViewer]側で
/// 分岐済み）。[autoPlay]がtrueの時だけ初期化後に自動再生する（プレビューから
/// 直接開いた対象のみtrue。スワイプ/矢印キーで切り替えた先はfalseになり、
/// 中央の再生ボタン（[_CenterControls]）をタップするまで一時停止のまま、
/// 2026-08-14追加）。再生/一時停止は、動画の座標上（レターボックスの余白
/// 含む）のどこをタップしても、またスペースキーでも切り替えられる
/// （[_togglePlayback]、スペースキーは[MediaViewerScreen]の`Focus`から
/// `GlobalKey`経由で呼び出す、2026-08-14追加）。ページを離れる際は[_pause]が
/// `_MediaViewerScreenState`の`onPageChanged`から同様に`GlobalKey`経由で
/// 呼ばれ、常に一時停止した状態でページを離れる（2026-09-06追加）。
class _VideoViewerPage extends StatefulWidget {
  const _VideoViewerPage({
    super.key,
    required this.url,
    required this.autoPlay,
  });

  final String url;
  final bool autoPlay;

  @override
  State<_VideoViewerPage> createState() => _VideoViewerPageState();
}

class _VideoViewerPageState extends State<_VideoViewerPage> {
  late final VideoPlayerController _controller;
  late final Future<void> _initializeFuture;

  /// 中央の再生/一時停止＋10秒送り/戻しボタンの表示状態
  /// （2026-08-18追加）。一時停止中は常時`true`（`build`側で
  /// `!isPlaying`と合わせて判定）、再生中はポインター移動のたびに
  /// `_resetControlsVisibility`で`true`に戻り、[_hideTimer]で数秒後に
  /// `false`へフェードアウトする。
  bool _controlsVisible = true;
  Timer? _hideTimer;

  /// シークバーのドラッグ中だけ使うローカルの再生位置（ミリ秒、
  /// 2026-08-18追加）。ドラッグ中は`ValueListenableBuilder`が拾う
  /// `_controller`側の位置と競合させず、この値をそのまま`Slider`へ
  /// 表示する。ドラッグ終了で`null`に戻す。
  double? _dragPositionMs;

  /// モバイル限定のダブルタップ10秒送り/戻し操作時に表示する
  /// フラッシュ文言（`+10秒`/`−10秒`、2026-08-18追加）。
  String? _skipFlashLabel;
  Timer? _skipFlashTimer;

  /// ダブルタップでの10秒送り/戻しをモバイル（Android/iOS）限定にする
  /// 判定（2026-08-18追加）。デスクトップ/Webで`onDoubleTapDown`を
  /// 常設すると、既存の動画本体クリック（`onTap: _togglePlayback`）が
  /// ダブルタップ判定待ちのため約300ms遅延してしまうため、モバイル以外
  /// では`onDoubleTapDown`自体を渡さない。
  bool get _isMobilePlatform =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _initializeFuture = _controller.initialize().then((_) {
      if (widget.autoPlay) _controller.play();
      if (mounted) setState(() {});
      _resetControlsVisibility();
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _skipFlashTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _togglePlayback() {
    setState(() {
      _controller.value.isPlaying ? _controller.pause() : _controller.play();
    });
    _resetControlsVisibility();
  }

  /// ページを離れる際に呼ばれる一時停止（2026-09-06追加、
  /// `_MediaViewerScreenState.onPageChanged`参照）。既に一時停止中なら
  /// 何もしない。
  void _pause() {
    if (_controller.value.isPlaying) {
      setState(() => _controller.pause());
    }
  }

  /// 中央コントロールを表示状態にし、再生中なら数秒後に自動的に
  /// 非表示へ戻すタイマーを（張り直して）セットする（2026-08-18追加）。
  /// 一時停止中はタイマーをセットしない（`build`側の`!isPlaying`判定で
  /// 常時表示になるため）。ポインター移動・タップでの再生/一時停止・
  /// 10秒送り/戻し操作のたびに呼び出す。
  void _resetControlsVisibility() {
    _hideTimer?.cancel();
    _hideTimer = null;
    setState(() => _controlsVisible = true);
    if (_controller.value.isPlaying) {
      _hideTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _controlsVisible = false);
      });
    }
  }

  /// 再生位置を[offset]分早送り/巻き戻しする（2026-08-14追加、
  /// `_buildControlBar`の10秒送り/戻しボタンで使う）。0秒〜動画の長さの
  /// 範囲にクランプする。`_controller`は`ValueNotifier`なので、
  /// `seekTo`後の位置反映は`_buildControlBar`の`ValueListenableBuilder`が
  /// 自動的に拾う（setState不要）。
  void _skip(Duration offset) {
    final target = _controller.value.position + offset;
    final duration = _controller.value.duration;
    _controller.seekTo(
      target < Duration.zero
          ? Duration.zero
          : (target > duration ? duration : target),
    );
  }

  /// モバイル限定のダブルタップ操作（2026-08-18追加）。タップ位置が
  /// 動画エリア（[areaWidth]、レターボックス含む）の右半分なら10秒送り、
  /// 左半分なら10秒戻し、あわせて[_showSkipFlash]で一瞬のフラッシュ表示。
  void _handleDoubleTapSkip(TapDownDetails details, double areaWidth) {
    final isRightHalf = details.localPosition.dx > areaWidth / 2;
    _skip(Duration(seconds: isRightHalf ? 10 : -10));
    _showSkipFlash(forward: isRightHalf);
    _resetControlsVisibility();
  }

  /// 「+10秒」「−10秒」を一瞬フラッシュ表示する（2026-08-18追加）。
  void _showSkipFlash({required bool forward}) {
    _skipFlashTimer?.cancel();
    setState(() => _skipFlashLabel = forward ? '+10秒' : '−10秒');
    _skipFlashTimer = Timer(const Duration(milliseconds: 600), () {
      if (mounted) setState(() => _skipFlashLabel = null);
    });
  }

  static String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  /// 再生/一時停止ボタン・現在位置/合計時間・白色のプログレスバー
  /// （2026-08-11追加）。再生位置は再生中も連続的に進むため、`_controller`
  /// （それ自体が`ValueNotifier<VideoPlayerValue>`）を`ValueListenableBuilder`
  /// で購読し、位置・再生状態の変化のたびに再描画する。
  Widget _buildControlBar() {
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: _controller,
      builder: (context, value, _) {
        final durationMs = value.duration.inMilliseconds.toDouble();
        final sliderMax = durationMs <= 0 ? 1.0 : durationMs;
        final sliderValue =
            (_dragPositionMs ?? value.position.inMilliseconds.toDouble()).clamp(
              0.0,
              sliderMax,
            );
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Text(
                _formatDuration(value.position),
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
              Expanded(
                // 現在の再生位置に丸（つまみ）を表示し、ドラッグでの
                // ホールドをしやすくする（2026-08-18追加）。背景の
                // `VideoProgressIndicator`（再生済み/バッファ済みの色分け、
                // `allowScrubbing: false`でジェスチャーを持たせない）に、
                // トラックを透明にした`Slider`を重ねてつまみとドラッグ
                // 操作だけを担わせる構成。両者はそれぞれ独自にトラック幅を
                // 計算するため水平方向のピクセル完全一致までは追求しない。
                child: SizedBox(
                  height: 24,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      VideoProgressIndicator(
                        _controller,
                        allowScrubbing: false,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        colors: const VideoProgressColors(
                          playedColor: Colors.white,
                          bufferedColor: Colors.white24,
                          backgroundColor: Colors.white10,
                        ),
                      ),
                      SliderTheme(
                        data: SliderThemeData(
                          trackHeight: 0,
                          activeTrackColor: Colors.transparent,
                          inactiveTrackColor: Colors.transparent,
                          thumbColor: Colors.white,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 6,
                          ),
                          overlayShape: const RoundSliderOverlayShape(
                            overlayRadius: 16,
                          ),
                          overlayColor: Colors.white24,
                        ),
                        child: Slider(
                          min: 0,
                          max: sliderMax,
                          value: sliderValue,
                          onChanged: durationMs <= 0
                              ? null
                              : (v) {
                                  setState(() => _dragPositionMs = v);
                                  _controller.seekTo(
                                    Duration(milliseconds: v.round()),
                                  );
                                },
                          onChangeEnd: (_) =>
                              setState(() => _dragPositionMs = null),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Text(
                _formatDuration(value.duration),
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _initializeFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.white),
          );
        }
        if (snapshot.hasError) {
          return const Center(
            child: Icon(Icons.error_outline, color: Colors.white, size: 48),
          );
        }
        // `AspectRatio`をそのまま`Center`直下に置くと、`Column`が
        // 主軸（縦）方向に無制限の高さを子へ渡すため、縦長（ポート
        // レート）動画で画面の高さを大きく超えるオーバーフローが
        // 発生した（2026-08-11発覚）。`Expanded`で明示的に高さを
        // 画面残り分に制限し、`AspectRatio`が幅・高さ両方の制約内で
        // 収まるサイズを計算できるようにする。
        //
        // タップ判定は`Expanded`領域全体（動画の周囲の黒い余白＝
        // レターボックス部分も含む）に対して行う（2026-08-14変更。以前は
        // `AspectRatio`の実サイズにだけ`GestureDetector`を付けていたため、
        // 動画の座標上でも余白部分をクリックすると反応しない不具合があった）。
        // 画像ページ（[_ImageViewerPage]）と異なり、動画本体のタップは
        // 「閉じる」ではなく常に再生/一時停止のトグルにするため、外側の
        // 「タップで閉じる」ジェスチャーは持たせない（閉じるのはEscキー・
        // 下スワイプ・AppBarの戻るボタンで行う。以前は動画全体を覆う
        // 「タップで閉じる」の`GestureDetector`とこのトグル用
        // `GestureDetector`が入れ子になっており、スワイプで動画ページへ
        // 遷移した直後は再生ボタンを押しても再生されない不具合があった。
        // 入れ子のジェスチャー判定自体を無くすことで解消した）。
        //
        // モバイル（`_isMobilePlatform`）ではタップで再生/一時停止を
        // トグルしない（2026-09-07変更）。画面タップはデスクトップ/Webで
        // ポインターを動かした時と同じ`_resetControlsVisibility`（操作
        // パネルの表示のみ）にする。再生/一時停止は`_CenterControls`の
        // 中央ボタン（下記、独立した`InkWell`を持つ）を押した時のみ行う。
        // これにより、以前はタップ用`onTap`とダブルタップ用
        // `onDoubleTapDown`が同じ`GestureDetector`上で競合し、ダブル
        // タップのつもりが「タップ2回」（一時停止→再生）としてしか
        // 認識されない不具合があったが、`onTap`が単なる表示更新になった
        // ことで解消する。デスクトップ/Webでは従来通りタップでのトグルを
        // 維持する（ユーザー要望の対象外のため）。
        return Column(
          children: [
            Expanded(
              child: MouseRegion(
                onHover: (_) => _resetControlsVisibility(),
                // ダブルタップの左右判定に動画エリアの幅が要るため
                // `LayoutBuilder`で包む（2026-08-18追加）。
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _isMobilePlatform
                          ? _resetControlsVisibility
                          : _togglePlayback,
                      // モバイル以外では`onDoubleTapDown`自体を渡さない
                      // （`_isMobilePlatform`のdocコメント参照。常設すると
                      // 全プラットフォームでシングルタップの確定が
                      // ダブルタップ判定待ちの分だけ遅延してしまうため）。
                      onDoubleTapDown: _isMobilePlatform
                          ? (details) => _handleDoubleTapSkip(
                              details,
                              constraints.maxWidth,
                            )
                          : null,
                      child: Center(
                        child: AspectRatio(
                          aspectRatio: _controller.value.aspectRatio,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              VideoPlayer(_controller),
                              // Web（video_player_web）は<video>要素を直接
                              // DOMへ描画するプラットフォームビューのため、
                              // 動画のピクセル上のクリックがFlutterの
                              // ジェスチャー検出まで届かないことがある
                              // （2026-08-19判明。レターボックス部分は
                              // Flutterが直接描画しているため外側の
                              // GestureDetectorで問題無く反応するが、動画
                              // 本体は無反応だった）。動画と同じ範囲を覆う
                              // 透明なオーバーレイをVideoPlayerの直後
                              // （＝より手前）に重ね、タップ/ダブルタップを
                              // こちらで捕捉し直す。外側のGestureDetector
                              // （レターボックス部分用）は引き続き維持する。
                              // ネイティブモバイル（`_isMobilePlatform`）は
                              // テクスチャ描画でこの問題が起きないため、
                              // このオーバーレイの`onTap`/`onDoubleTapDown`
                              // 自体を持たせない（2026-09-07変更）。外側と
                              // 内側の両方が同じ座標で`TapGestureRecognizer`/
                              // `DoubleTapGestureRecognizer`を二重に
                              // ジェスチャーアリーナへ登録してしまい、
                              // ダブルタップが安定して認識されなかった
                              // 不具合の根本原因だったため。
                              Positioned.fill(
                                child: LayoutBuilder(
                                  builder: (context, videoConstraints) {
                                    return GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTap: _isMobilePlatform
                                          ? null
                                          : _togglePlayback,
                                      // ダブルタップ10秒送り/戻しはモバイル
                                      // 限定の機能で、モバイルでは外側の
                                      // `GestureDetector`だけが担う
                                      // （上記コメント参照）ため、ここでは
                                      // プラットフォームに関わらず常に
                                      // 設定しない。
                                      onDoubleTapDown: null,
                                    );
                                  },
                                ),
                              ),
                              // 一時停止中は常時、再生中はポインター移動から
                              // 数秒間だけ、中央に再生/一時停止＋10秒送り/戻し
                              // ボタンを表示する（2026-08-14追加・2026-08-18に
                              // 10秒送り/戻し追加＋ポインター連動化）。個々の
                              // ボタンは実際にタップを受け取るため、外側の
                              // `onTap: _togglePlayback`（動画本体タップでの
                              // トグル）とは独立して共存する。
                              if (!_controller.value.isPlaying ||
                                  _controlsVisible)
                                _CenterControls(
                                  isPlaying: _controller.value.isPlaying,
                                  onTogglePlayback: _togglePlayback,
                                  onSkipBack: () {
                                    _skip(const Duration(seconds: -10));
                                    _resetControlsVisibility();
                                  },
                                  onSkipForward: () {
                                    _skip(const Duration(seconds: 10));
                                    _resetControlsVisibility();
                                  },
                                ),
                              // モバイルでのダブルタップ10秒送り/戻し操作の
                              // フィードバック（2026-08-18追加）。中央の
                              // `_CenterControls`と重ならないよう上寄せに
                              // 配置する。
                              if (_skipFlashLabel != null)
                                Align(
                                  alignment: const Alignment(0, -0.5),
                                  child: IgnorePointer(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.black54,
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        _skipFlashLabel!,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            // 中央の再生/一時停止＋10秒送り/戻しボタンと同じ条件で
            // 表示/非表示を切り替える（2026-09-05変更、以前は常時表示
            // だった）。`Column`の兄弟要素のため単純に`if`で取り除くと
            // 動画エリアが伸びてガタつくので、`maintainSize`で領域だけ
            // 保持したまま非表示にする。
            Visibility(
              visible: !_controller.value.isPlaying || _controlsVisible,
              maintainSize: true,
              maintainAnimation: true,
              maintainState: true,
              child: _buildControlBar(),
            ),
          ],
        );
      },
    );
  }
}

/// 動画中央に表示する再生/一時停止＋10秒送り/戻しの3ボタン
/// （[_VideoViewerPage]参照、2026-08-14追加・2026-08-18に10秒送り/戻し
/// ボタンを追加）。各ボタンは[_CircleIconButton]で実際にタップを
/// 受け取るため、外側の`GestureDetector`（動画本体タップ、デスクトップ/Webは
/// `_togglePlayback`・モバイルは`_resetControlsVisibility`、2026-09-07
/// 変更）とは独立して動作する。モバイルでは再生/一時停止はこの中央ボタン
/// からのみ行える。
class _CenterControls extends StatelessWidget {
  const _CenterControls({
    required this.isPlaying,
    required this.onTogglePlayback,
    required this.onSkipBack,
    required this.onSkipForward,
  });

  final bool isPlaying;
  final VoidCallback onTogglePlayback;
  final VoidCallback onSkipBack;
  final VoidCallback onSkipForward;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _CircleIconButton(
          icon: Icons.replay_10,
          size: 44,
          iconSize: 26,
          onTap: onSkipBack,
        ),
        const SizedBox(width: 20),
        _CircleIconButton(
          icon: isPlaying ? Icons.pause : Icons.play_arrow,
          size: 64,
          iconSize: 40,
          onTap: onTogglePlayback,
        ),
        const SizedBox(width: 20),
        _CircleIconButton(
          icon: Icons.forward_10,
          size: 44,
          iconSize: 26,
          onTap: onSkipForward,
        ),
      ],
    );
  }
}

/// [_CenterControls]の3ボタンで共通に使う黒45%円・白アイコンの
/// タップ可能なボタン（2026-08-18追加）。
class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({
    required this.icon,
    required this.size,
    required this.iconSize,
    required this.onTap,
  });

  final IconData icon;
  final double size;
  final double iconSize;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black45,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon, color: Colors.white, size: iconSize),
        ),
      ),
    );
  }
}
