import 'package:flutter/material.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../../router/back_stack.dart';
import '../../theme/motion.dart';
import '../../widgets/transitioned_overlay.dart';
import 'bgm/call_bgm_sheet.dart' show CallPanelSurface;

/// 通話のBGM・サウンドボードのボトムシート（2026-11-17）。画面を覆う暗幕は出さず、シート
/// だけを、設定の「画面遷移」の種類に関係なく、下からスライドして出し入れする。外側のクリック
/// （見えない障壁）・Esc・戻るで閉じる。
///
/// PC・Webの通話画面（`CallOverlay`）は`MaterialApp.builder`の位置にありNavigatorが無く、
/// `showModalBottomSheet`は例外になる為、専用の`Overlay`へ直接出す。
Future<void> showCallBottomSheet(
  BuildContext context, {
  required WidgetBuilder builder,
}) {
  if (Navigator.maybeOf(context) == null) {
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return Future.value();
    showTransitionedOverlay(
      overlay,
      transitionBuilder: _slideUp,
      builder: (context, close) => PointerInterceptor(
        child: BackEntry(
          scope: null,
          active: true,
          layer: true,
          onBack: close,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 見えない障壁。Webでは映像（プラットフォームビュー）がクリックを奪う為、
              // `PointerInterceptor`で受ける。
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: close,
                child: const SizedBox.expand(),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: CallPanelSurface(child: Builder(builder: builder)),
              ),
            ],
          ),
        ),
      ),
    );
    return Future.value();
  }
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.transparent,
    elevation: 0,
    builder: (context) => CallPanelSurface(child: Builder(builder: builder)),
  );
}

/// 下から上へスライドして現れ、閉じる時は下へ戻る（ポップ演出と同じ曲線・長さ）。
Widget _slideUp(Animation<double> animation, Widget child) {
  final curved = CurvedAnimation(
    parent: animation,
    curve: popSlideCurve,
    reverseCurve: popSlideCurve,
  );
  return SlideTransition(
    position: Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(curved),
    child: child,
  );
}
