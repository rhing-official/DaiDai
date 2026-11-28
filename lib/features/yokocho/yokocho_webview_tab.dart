import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../models/app_user.dart';
import '../../models/nav_chip_layout.dart';
import '../../providers/home_shell_providers.dart';
import '../../providers/nav_chip_layout_provider.dart';
import '../../providers/slide_transition_style_provider.dart';
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
  Brightness? _loadedBrightness;

  /// 最後に差し込んだスクリプト。今の内容と違えば、差し込み直す（背景の設定が変わった時や、
  /// 開発中のホットリロードで差し込みの内容が変わった時に、ページを読み直さず反映する為）。
  String? _appliedScript;
  Timer? _preloadTimer;

  /// アプリを開いてから、裏で横丁を読み込み始めるまでの待ち。起動の処理と競わせない為。
  static const _preloadDelay = Duration(seconds: 2);

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      // トップページでの横スワイプを、タブの移動として受け取る（差し込みの`DaidaiTab.postMessage`）。
      ..addJavaScriptChannel(
        'DaidaiTab',
        onMessageReceived: (message) {
          final delta = switch (message.message) {
            'prev' => -1,
            'next' => 1,
            _ => 0,
          };
          if (delta != 0) {
            ref.read(homeTabStepProvider.notifier).step(delta);
          }
        },
      )
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
          onPageStarted: (_) => _injectStyle(),
          onPageFinished: (_) {
            _injectStyle();
            _refreshBack();
          },
          onUrlChange: (_) {
            _injectStyle();
            _refreshBack();
          },
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
    if (!mounted) return;
    // 戻る要求で`BackEntry`が外れた後も、まだ戻れるなら積み直す為、値が同じでも組み直す。
    setState(() {
      _canGoBack = canGoBack;
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

  /// ページ移動の動き（2026-11-29）。設定の「画面遷移」（[SlideTransitionStyle]）を、横丁の中の
  /// ページ移動にも当てる。新しいページの内容（`main`）が、設定の動きで現れる。戻る（右スワイプ・
  /// 戻るボタン）はスライドが左から、進むと新しい移動は右から。吸い込み・ポップ・描きは向きに依らない。
  /// 設定は`window.__daidaiTransCfg`（style・ms）で受け取る。何度差し込んでも、見張りは1組だけ。
  /// 描きは、ペンの往復ではなく、下から上への塗り広げで近似する。
  static const _transitionJs = r'''
(function(){
  if(window.__daidaiTransOff)window.__daidaiTransOff();
  var EASE_OUT="cubic-bezier(0.215,0.61,0.355,1)";
  var EASE_BACK="cubic-bezier(0.34,1.56,0.64,1)";
  var EASE_IO="cubic-bezier(0.42,0,0.58,1)";
  var dir="forward";
  var timer=null;
  function animate(d){
    var cfg=window.__daidaiTransCfg||{};
    var main=document.querySelector("main");
    if(!main)return;
    // 右上のバー（position:fixed、`.recede-hide.fixed`）は、`main`の中の入れ物の中に有る。入れ物を
    // 変形させると、固定表示も一緒に動く（変形した要素が、固定表示の基準になる）為、バーを含む入れ物は
    // 動かさず、その中の、バーを含まない要素だけを動かす。
    var targets=[];
    var collect=function(node){
      for(var i=0;i<node.children.length;i++){
        var c=node.children[i];
        if(getComputedStyle(c).position==="fixed")continue;
        if(c.querySelector(".recede-hide.fixed"))collect(c);else targets.push(c);
      }
    };
    collect(main);
    if(!targets.length||!targets[0].animate)return;
    var s=cfg.style,ms=cfg.ms||220;
    var x=d==="back"?"-100%":"100%";
    var root=document.documentElement;
    var prevX=root.style.overflowX;
    root.style.overflowX="hidden";
    var opts=function(easing){return {duration:ms,easing:easing,fill:"none"};};
    var first=null;
    var run=function(el,kf,easing){
      var a=el.animate(kf,opts(easing));
      if(!first)first=a;
    };
    for(var k=0;k<targets.length;k++){
      var el=targets[k];
      if(s==="slideBlur"){
        run(el,[{transform:"translateX("+x+")",opacity:0,filter:"blur(10px)"},{transform:"none",opacity:1,filter:"blur(0)"}],EASE_OUT);
      }else if(s==="slide"){
        run(el,[{transform:"translateX("+x+")"},{transform:"none"}],EASE_OUT);
      }else if(s==="suck"){
        el.style.transformOrigin="100% 100%";
        run(el,[{transform:"scale(0.1)",opacity:0,filter:"blur(10px)"},{transform:"none",opacity:1,filter:"blur(0)"}],EASE_OUT);
      }else if(s==="pop"){
        el.style.transformOrigin="50% 50%";
        run(el,[{transform:"scale(0.6)"},{transform:"none"}],EASE_BACK);
        run(el,[{opacity:0},{opacity:1}],EASE_OUT);
      }else if(s==="draw"){
        run(el,[{clipPath:"inset(100% 0 0 0)"},{clipPath:"inset(0 0 0 0)"}],EASE_IO);
      }
    }
    var done=function(){
      root.style.overflowX=prevX;
      for(var j=0;j<targets.length;j++)targets[j].style.transformOrigin="";
    };
    if(first){first.onfinish=done;first.oncancel=done;}else done();
  }
  function schedule(d){
    clearTimeout(timer);
    timer=setTimeout(function(){animate(d);},80);
  }
  function onNavigate(e){
    var d="forward";
    if(e.navigationType==="traverse"&&e.destination&&window.navigation&&navigation.currentEntry){
      d=e.destination.index<navigation.currentEntry.index?"back":"forward";
    }
    dir=d;
    try{sessionStorage.setItem("__daidaiDir",d);}catch(_){}
    if(e.destination&&e.destination.sameDocument)schedule(d);
  }
  var onPop=function(){dir="back";schedule("back");};
  if(window.navigation&&navigation.addEventListener){
    navigation.addEventListener("navigate",onNavigate);
  }else{
    window.addEventListener("popstate",onPop);
  }
  window.__daidaiTransOff=function(){
    clearTimeout(timer);
    if(window.navigation&&navigation.removeEventListener)navigation.removeEventListener("navigate",onNavigate);
    window.removeEventListener("popstate",onPop);
  };
  // ページを読み込み直した時（ページ全体の移動）は、直前に記録した向きで、1回だけ動かす。最初の読み込みは動かさない。
  if(!window.__daidaiLoadAnimated){
    window.__daidaiLoadAnimated=true;
    var seen=false,d0="forward";
    try{
      seen=sessionStorage.getItem("__daidaiSeen")==="1";
      d0=sessionStorage.getItem("__daidaiDir")||"forward";
      sessionStorage.setItem("__daidaiSeen","1");
      sessionStorage.removeItem("__daidaiDir");
    }catch(_){}
    if(seen){
      if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",function(){schedule(d0);});
      else schedule(d0);
    }
  }
})();
''';

  /// アプリで開いた横丁にだけ当てるCSS。横丁のサイトの実装は変えず、アプリ側から差し込む
  /// （2026-11-29、ユーザー指示）。
  ///
  /// - 左上: ホームページでRhingのロゴが有る場所に、「daidai横丁」を置く。押すと横丁のトップへ移る。
  ///   要素は[_injectStyle]が作る（`#daidai-app-home`）。
  /// - 右上: バー（お気に入り・カート・アカウント）は、ホームページのバーと同じ並び（左からお気に入り、
  ///   カート、アカウント）で、チップの間を縦線にして、上の端へ寄せる。ホームページの実装は
  ///   `DaidaiYokochoMenu.tsx`。狭い画面では、元の区切りが横線（`h-px w-6`）になる為、縦線に直す。
  ///   見た目は、ホームページのヘッダーのバー（半透明の面・細い縁・影・ぼかし・丸いボタン）に揃える。
  ///   ホームページのバーに入っているハンバーガーとモード切り替えは、入れない。
  static const _injectedCss = r'''
main{padding-top:4.5rem!important}
nav[aria-label="お気に入り・カート・アカウント"]{flex-direction:row!important;background:color-mix(in srgb,var(--color-surface) 80%,transparent)!important;border:1px solid color-mix(in srgb,var(--color-outline-variant) 60%,transparent)!important;box-shadow:var(--shadow-elevation-3)!important;-webkit-backdrop-filter:blur(12px)!important;backdrop-filter:blur(12px)!important;border-radius:9999px!important}
nav[aria-label="お気に入り・カート・アカウント"]>span[aria-hidden]{width:1px!important;height:1.5rem!important}
nav[aria-label="お気に入り・カート・アカウント"] a,nav[aria-label="お気に入り・カート・アカウント"] button{border-radius:9999px!important}
.recede-hide.fixed{top:.75rem!important;right:.75rem!important;left:auto!important}
#daidai-app-home{position:absolute;top:.75rem;left:1rem;height:48px;display:flex;align-items:center;z-index:50;font-family:var(--font-sans),sans-serif;font-size:1.25rem;font-weight:500;letter-spacing:.15em;color:var(--color-on-surface);text-decoration:none;-webkit-tap-highlight-color:transparent}
''';

  /// 背景をアプリの設定に合わせ、[_injectedCss]を差し込む。何度呼んでも同じ結果になる。
  /// 読み込みの始め・終わり・ページの移動のたびに呼ぶ（ページが作り直されても、差し込みが残るように）。
  String _injectionScript() {
    final hex = _backgroundHex();
    final transition = ref.read(slideTransitionStyleProvider);
    return '''
(function(){
  var e=document.documentElement;
  if(!e)return;
  e.style.setProperty("--color-surface","#$hex");
  var id="daidai-app-style";
  var st=document.getElementById(id);
  if(!st){st=document.createElement("style");st.id=id;(document.head||e).appendChild(st);}
  st.textContent=${jsonEncode(_injectedCss)};
  if(!window.__daidaiTitleObserver){
    var hideTitle=function(){
      var hs=document.querySelectorAll("h1");
      for(var i=0;i<hs.length;i++){
        var h=hs[i];
        if(h.textContent.trim()==="daidai横丁"){
          var box=h.closest(".container")||h.parentElement;
          if(box)box.style.display="none";
        }
      }
    };
    hideTitle();
    window.__daidaiTitleObserver=new MutationObserver(hideTitle);
    window.__daidaiTitleObserver.observe(document.documentElement,{childList:true,subtree:true});
  }
  if(document.body&&!document.getElementById("daidai-app-home")){
    var a=document.createElement("a");
    a.id="daidai-app-home";
    a.href="/daidai-yokocho";
    a.textContent="daidai横丁";
    document.body.appendChild(a);
  }
})();
(function(){
  if(window.__daidaiSwipeOff)window.__daidaiSwipeOff();
  var sx=0,sy=0,st=0,ok=false;
  function hscroll(el){
    while(el&&el!==document.body){
      var cs=getComputedStyle(el);
      if((cs.overflowX==="auto"||cs.overflowX==="scroll")&&el.scrollWidth>el.clientWidth+1)return true;
      el=el.parentElement;
    }
    return false;
  }
  function ts(e){
    if(e.touches.length!==1){ok=false;return;}
    var t=e.touches[0];
    sx=t.clientX;sy=t.clientY;st=Date.now();
    var w=window.innerWidth;
    ok=sx>24&&sx<w-24&&!hscroll(e.target)&&!/^(INPUT|TEXTAREA|SELECT)\$/.test(e.target.tagName);
  }
  function te(e){
    if(!ok)return;
    ok=false;
    var t=e.changedTouches[0];
    var dx=t.clientX-sx,dy=t.clientY-sy,dt=Date.now()-st;
    if(Math.abs(dx)<80||Math.abs(dy)>Math.abs(dx)*0.5||dt>600)return;
    // トップページ（一覧）を開いている間は、タブの移動にする。右へ引けば前のタブ、左へ引けば、
    // 進めるときは進み、進めなければ次のタブ。それ以外のページは、戻る・進む。
    var top=location.pathname.replace(/\\/+\$/,"")==="/daidai-yokocho";
    var tab=function(d){if(window.DaidaiTab)DaidaiTab.postMessage(d);};
    if(top){
      if(dx>0)tab("prev");
      else if(window.navigation&&navigation.canGoForward)history.forward();
      else tab("next");
    }else{
      if(dx>0)history.back();else history.forward();
    }
  }
  document.addEventListener("touchstart",ts,{passive:true});
  document.addEventListener("touchend",te,{passive:true});
  window.__daidaiSwipeOff=function(){
    document.removeEventListener("touchstart",ts);
    document.removeEventListener("touchend",te);
  };
})();

window.__daidaiTransCfg=${jsonEncode({'style': transition.name, 'ms': transition.usesDraw ? 420 : 220})};
$_transitionJs
''';
  }

  Future<void> _injectStyle() async {
    if (!mounted) return;
    final js = _injectionScript();
    _appliedScript = js;
    try {
      await _controller.runJavaScript(js);
    } catch (_) {
      // ページがまだ作られていない間は、次の呼び出しで差し込む。
    }
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
      },
      fragment: token == null ? null : 'token=$token',
    );
    await _controller.loadRequest(uri);
  }

  @override
  Widget build(BuildContext context) {
    // 初めて開いた時に待たされないよう、アプリを開いて少し経ったら、裏で読み込み始める
    // （2026-11-29）。タブを先に開いた場合は、その場で始める。チップを消している間は読まない。
    // 画面遷移の設定が変わったら、差し込み直す（`_injectionScript`の中身が変わる）。
    ref.watch(slideTransitionStyleProvider);
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
        if (mounted && _appliedScript != _injectionScript()) {
          _injectStyle();
        }
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
              if (_failed)
                Center(
                  child: GestureDetector(
                    onTap: _start,
                    child: Icon(Icons.refresh, size: 32, color: palette.subtle),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
