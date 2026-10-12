import 'package:flutter/material.dart';

import '../models/app_user.dart';
import 'profile_card_view.dart';

/// [user]が[conversationId]（一対のdmId・広場のgroupId）で見せるプロフィールカード
/// （会話ごとに選んだ工房カード、無ければ標準）を[ProfileCardView]で描く
/// （2026-10-13、`UserProfileCardDialog`と語らい一覧のホバーカードで共通化）。
/// 呼び名は未設定なら`@rhingSeed`にフォールバックする。
class UserProfileCardView extends StatelessWidget {
  const UserProfileCardView({
    required this.user,
    required this.width,
    required this.height,
    this.conversationId,
    this.showSnsLinks = true,
    super.key,
  });

  final AppUser user;
  final String? conversationId;
  final double width;
  final double height;

  /// カード内にSNSのURLを出すか。ダイアログはカードの下にタップできる別要素で
  /// 出すためfalse、操作できないホバーカードはtrue。
  final bool showSnsLinks;

  @override
  Widget build(BuildContext context) {
    final card = user.profileCardFor(conversationId);
    final nickname = user.effectiveNicknameFor(conversationId);
    final name = (nickname?.text.isNotEmpty ?? false)
        ? nickname!.text
        : '@${user.rhingSeed}';
    return ProfileCardView(
      width: width,
      height: height,
      icon: user.effectiveIconFor(conversationId),
      background: user.effectiveBackgroundImageFor(conversationId),
      backgroundFocal: card?.backgroundFocal,
      iconFocal: card?.iconFocal,
      layoutPreset: card?.layoutPreset,
      textAlign: card?.textAlign,
      nickname: name,
      statusMessage: user.effectiveStatusMessageFor(conversationId)?.text,
      snsLinks: showSnsLinks
          ? user.effectiveSnsLinksFor(conversationId)
          : const [],
      fontFamily: user.effectiveFontDesignFor(conversationId)?.fontFamily,
    );
  }
}
