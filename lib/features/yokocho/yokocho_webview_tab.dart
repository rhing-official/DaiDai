import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../models/app_user.dart';
import '../../models/nav_chip_layout.dart';
import '../../providers/home_shell_providers.dart';
import '../../providers/nav_chip_layout_provider.dart';
import '../../router/back_stack.dart';
import '../../services/app_functions.dart';
import '../../utils/yokocho.dart';
import 'yokocho_palette.dart';
import 'yokocho_tab.dart';

/// ホームの「横丁」タブ（2026-11-28）。Android・iOSでは、横丁のWeb（HomePage）を
/// WebViewでそのまま開く。見た目・機能は横丁と同じで、横丁を直せばアプリの更新無しで反映される。
/// Web版のアプリはWebViewが使えないので、Dart版の[YokochoNativeTab]を出す。
///
/// 横丁とアプリはログイン状態を共有しない。開く時にCloud Functions `createWebSignInToken`で
/// 使い捨てのカスタムトークンを受け取り、URLのハッシュで渡して、横丁側が同じアカウントで入る。
/// ヘッダー等を隠す`embed=1`と、有料の価格・購入の導線を隠す処理は、横丁側が受け持つ。
class YokochoTab extends ConsumerWidget {
  const YokochoTab({required this.currentUser, super.key});

  final AppUser currentUser;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!yokochoWebViewAvailable()) {
      return YokochoNativeTab(currentUser: currentUser);
    }
    return _YokochoWebViewTab(currentUser: currentUser);
  }
}

class _YokochoWebViewTab extends ConsumerStatefulWidget {
  const _YokochoWebViewTab({required this.currentUser});

  final AppUser currentUser;

  @override
  ConsumerState<_YokochoWebViewTab> createState() => _YokochoWebViewTabState();
}

class _YokochoWebViewTabState extends ConsumerState<_YokochoWebViewTab> {
  static const _hosts = {'rhing.jp', 'www.rhing.jp'};

  late final WebViewController _controller;
  bool _activated = false;
  bool _failed = false;
  bool _canGoBack = false;
  bool _canGoForward = false;
  Brightness? _loadedBrightness;
  String? _appliedBackground;
  Timer? _preloadTimer;

  /// アプリを開いてから、裏で横丁を読み込み始めるまでの待ち。起動の処理と競わせない為。
  static const _preloadDelay = Duration(seconds: 2);

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            if (uri == null || _hosts.contains(uri.host)) {
              return NavigationDecision.navigate;
            }
            // 横丁の外のサイトは、アプリ内で開かず、ブラウザへ渡す。
            launchUrl(uri, mode: LaunchMode.externalApplication);
            return NavigationDecision.prevent;
          },
          onPageFinished: (_) => _refreshBack(),
          onUrlChange: (_) => _refreshBack(),
          onWebResourceError: (error) {
            if (error.isForMainFrame ?? false) {
              if (mounted) setState(() => _failed = true);
            }
          },
        ),
      );
  }

  @override
  void dispose() {
    _preloadTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _YokochoWebViewTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentUser.userId != widget.currentUser.userId &&
        _activated) {
      _start();
    }
  }

  Future<void> _refreshBack() async {
    final canGoBack = await _controller.canGoBack();
    final canGoForward = await _controller.canGoForward();
    if (!mounted) return;
    // 戻る要求で`BackEntry`が外れた後も、まだ戻れるなら積み直す為、値が同じでも組み直す。
    setState(() {
      _canGoBack = canGoBack;
      _canGoForward = canGoForward;
    });
  }

  /// アプリの背景色（設定>背景、UIスタイル、ダークの種類を全て反映した、今の画面の背景）を、
  /// `RRGGBB`で返す。横丁の背景だけを、これに合わせる（2026-11-29）。
  String _backgroundHex() {
    final c = Theme.of(context).scaffoldBackgroundColor;
    int ch(double v) => (v * 255).round().clamp(0, 255);
    String two(double v) => ch(v).toRadixString(16).padLeft(2, '0');
    return '${two(c.r)}${two(c.g)}${two(c.b)}';
  }

  /// 読み込み済みの横丁の背景色を、読み直さずに差し替える。
  void _syncBackground() {
    final hex = _backgroundHex();
    if (_appliedBackground == hex) return;
    _appliedBackground = hex;
    _controller.runJavaScript(
      'window.__daidaiSetBackground&&window.__daidaiSetBackground("$hex")',
    );
  }

  void _activate() {
    _activated = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _start();
    });
  }

  Future<void> _start() async {
    final brightness = Theme.of(context).brightness;
    _loadedBrightness = brightness;
    final background = _backgroundHex();
    _appliedBackground = background;
    final platform = Theme.of(context).platform == TargetPlatform.iOS
        ? 'ios'
        : 'android';
    if (mounted) setState(() => _failed = false);
    await _controller.setBackgroundColor(
      Theme.of(context).scaffoldBackgroundColor,
    );
    String? token;
    try {
      final result = await AppFunctions.instanceFor(
        region: 'asia-northeast1',
      ).httpsCallable('createWebSignInToken').call();
      token = (result.data as Map)['customToken'] as String?;
    } catch (_) {
      // トークンを受け取れなくても、横丁は未ログインで見られる。
    }
    final uri = Uri.parse(kYokochoUrl).replace(
      queryParameters: {
        'embed': '1',
        'platform': platform,
        'theme': brightness == Brightness.dark ? 'dark' : 'light',
        'bg': background,
      },
      fragment: token == null ? null : 'token=$token',
    );
    await _controller.loadRequest(uri);
  }

  /// 左端から右へ引けば戻る、右端から左へ引けば進む（ブラウザと同じ、2026-11-29）。
  /// WebViewの上に、画面の両端だけ細い帯を置き、横のドラッグだけを受ける。
  void _onEdgeDragEnd(DragEndDetails details, {required bool fromLeft}) {
    final v = details.primaryVelocity ?? 0;
    if (fromLeft && v > 150 && _canGoBack) {
      _controller.goBack();
    } else if (!fromLeft && v < -150 && _canGoForward) {
      _controller.goForward();
    }
  }

  Widget _edgeStrip({required bool fromLeft}) => Positioned(
    left: fromLeft ? 0 : null,
    right: fromLeft ? null : 0,
    top: 0,
    bottom: 0,
    width: 20,
    child: GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragEnd: (d) => _onEdgeDragEnd(d, fromLeft: fromLeft),
    ),
  );

  @override
  Widget build(BuildContext context) {
    // 初めて開いた時に待たされないよう、アプリを開いて少し経ったら、裏で読み込み始める
    // （2026-11-29）。タブを先に開いた場合は、その場で始める。チップを消している間は読まない。
    final selected =
        ref.watch(homeSelectedTabProvider) == HomeTabId.yokocho.index;
    final chipEnabled = ref.watch(
      navChipLayoutProvider.select((l) => l.yokochoChipEnabled),
    );
    if (!_activated) {
      if (selected) {
        _preloadTimer?.cancel();
        _activate();
      } else if (chipEnabled && _preloadTimer == null) {
        _preloadTimer = Timer(_preloadDelay, () {
          if (mounted && !_activated) setState(_activate);
        });
      }
    }
    final palette = YokochoPalette.of(context);
    // アプリの明るさが変わったら、横丁もその明るさで読み込み直す。
    if (_activated &&
        _loadedBrightness != null &&
        _loadedBrightness != Theme.of(context).brightness) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _start();
      });
    }

    if (_activated) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _syncBackground();
      });
    }

    return BackEntry(
      // 画面の戻る・Androidの戻るも、横丁の中のページを戻す。
      active: _activated && _canGoBack,
      scope: BackScope.yokocho,
      onBack: () => _controller.goBack(),
      onForward: () => _controller.goForward(),
      child: ColoredBox(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: SafeArea(
          bottom: false,
          child: Stack(
            children: [
              if (_activated) WebViewWidget(controller: _controller),
              if (_activated) ...[
                _edgeStrip(fromLeft: true),
                _edgeStrip(fromLeft: false),
              ],
              if (_failed)
                Center(
                  child: GestureDetector(
                    onTap: _start,
                    child: Icon(Icons.refresh, size: 32, color: palette.subtle),
                  ),
                ),
              // 横丁のヘッダーを隠しているので、詳細などから戻る手段を、ここに置く。
              if (_canGoBack)
                Positioned(
                  left: 12,
                  top: 8,
                  child: Material(
                    color: palette.card.withValues(alpha: 0.9),
                    shape: CircleBorder(
                      side: BorderSide(color: palette.outlineVariant),
                    ),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => _controller.goBack(),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Icon(
                          Icons.arrow_back,
                          size: 22,
                          color: palette.onSurface,
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
  }
}
