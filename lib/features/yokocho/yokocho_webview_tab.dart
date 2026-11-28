import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../models/app_user.dart';
import '../../models/nav_chip_layout.dart';
import '../../providers/home_shell_providers.dart';
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
  Brightness? _loadedBrightness;

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
  void didUpdateWidget(covariant _YokochoWebViewTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentUser.userId != widget.currentUser.userId &&
        _activated) {
      _start();
    }
  }

  Future<void> _refreshBack() async {
    final canGoBack = await _controller.canGoBack();
    if (mounted && canGoBack != _canGoBack) {
      setState(() => _canGoBack = canGoBack);
    }
  }

  Future<void> _start() async {
    final brightness = Theme.of(context).brightness;
    _loadedBrightness = brightness;
    final platform = Theme.of(context).platform == TargetPlatform.iOS
        ? 'ios'
        : 'android';
    if (mounted) setState(() => _failed = false);
    await _controller.setBackgroundColor(YokochoPalette.of(context).surface);
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
      },
      fragment: token == null ? null : 'token=$token',
    );
    await _controller.loadRequest(uri);
  }

  @override
  Widget build(BuildContext context) {
    // 最初に横丁のタブを開いた時だけ、読み込みを始める（開かない人には、通信もトークンの発行もしない）。
    final selected =
        ref.watch(homeSelectedTabProvider) == HomeTabId.yokocho.index;
    if (selected && !_activated) {
      _activated = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _start();
      });
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

    return ColoredBox(
      color: palette.surface,
      child: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            if (_activated) WebViewWidget(controller: _controller),
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
    );
  }
}
