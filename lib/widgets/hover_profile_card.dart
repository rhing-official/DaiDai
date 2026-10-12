import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/app_user.dart';
import '../utils/platform_info.dart';
import 'user_profile_card_view.dart';

/// ホバーカードを出すまでの待ち時間。
const kHoverProfileCardDelay = Duration(seconds: 2);

/// ホバーカードの大きさ（身だしなみカードと同じ4:5）。
const kHoverProfileCardSize = Size(260, 325);

/// カード（[card]）をタイルの**右上**に出す位置（左上座標）を求める（2026-10-13）。
/// 基本はタイル[tile]の右端の外側に、上端を揃えて置く。右に収まらなければタイルの
/// 左側へ、縦は画面[screen]内に収まるよう補正する。
Offset hoverProfileCardOffset({
  required Rect tile,
  required Size screen,
  Size card = kHoverProfileCardSize,
  double gap = 8,
  double margin = 8,
}) {
  var left = tile.right + gap;
  if (left + card.width > screen.width - margin) {
    final onLeft = tile.left - gap - card.width;
    left = onLeft >= margin
        ? onLeft
        : (screen.width - margin - card.width).clamp(margin, double.infinity);
  }
  final maxTop = math.max(margin, screen.height - margin - card.height);
  final top = tile.top.clamp(margin, maxTop);
  return Offset(left, top);
}

/// 語らい一覧の一対のブロックに、マウスを[kHoverProfileCardDelay]（2秒）以上
/// 乗せ続けると、相手のプロフィールカード（会話用に選んだ工房カード）をブロックの
/// 右上に出す（2026-10-13、工房カードの実利用箇所）。コンピューター
/// （`classifyDevice`が`computer`）だけで有効、タッチ端末では何もしない。
/// マウスが外れる・クリック・スクロール・ウィジェットの破棄で閉じる。ポップアップは
/// `IgnorePointer`で、一覧のタップ・右クリック・ドラッグ操作を妨げない。
class HoverProfileCard extends StatefulWidget {
  const HoverProfileCard({
    required this.user,
    required this.conversationId,
    required this.child,
    super.key,
  });

  /// 相手。まだ読み込めていない（null）間は出さない。
  final AppUser? user;
  final String conversationId;
  final Widget child;

  @override
  State<HoverProfileCard> createState() => _HoverProfileCardState();
}

class _HoverProfileCardState extends State<HoverProfileCard> {
  Timer? _timer;
  OverlayEntry? _entry;
  ScrollPosition? _scrollPosition;

  void _onEnter() {
    if (classifyDevice(context) != DeviceClass.computer) return;
    _timer?.cancel();
    _timer = Timer(kHoverProfileCardDelay, _show);
  }

  void _show() {
    final user = widget.user;
    final box = context.findRenderObject();
    if (!mounted || user == null || box is! RenderBox || !box.attached) return;
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;
    final tile = box.localToGlobal(Offset.zero) & box.size;
    final screen = MediaQuery.sizeOf(context);
    final offset = hoverProfileCardOffset(tile: tile, screen: screen);
    final conversationId = widget.conversationId;
    _entry = OverlayEntry(
      builder: (context) => Positioned(
        left: offset.dx,
        top: offset.dy,
        width: kHoverProfileCardSize.width,
        height: kHoverProfileCardSize.height,
        child: IgnorePointer(
          child: UserProfileCardView(
            user: user,
            conversationId: conversationId,
            width: kHoverProfileCardSize.width,
            height: kHoverProfileCardSize.height,
          ),
        ),
      ),
    );
    overlay.insert(_entry!);
    // スクロールするとブロックの位置がずれるため閉じる。
    _scrollPosition = Scrollable.maybeOf(context)?.position
      ?..addListener(_hide);
  }

  void _hide() {
    _timer?.cancel();
    _timer = null;
    _scrollPosition?.removeListener(_hide);
    _scrollPosition = null;
    _entry?.remove();
    _entry = null;
  }

  @override
  void dispose() {
    _hide();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => _onEnter(),
      onExit: (_) => _hide(),
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _hide(),
        child: widget.child,
      ),
    );
  }
}
