import 'package:flutter/material.dart';

import '../l10n/app_locale.dart';
import '../l10n/strings.dart';
import '../models/app_user.dart';
import '../models/profile_material.dart';
import '../utils/birthday_format.dart';
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
    this.copyRhingSeed = false,
    this.onOpenSnsLink,
    super.key,
  });

  final AppUser user;
  final String? conversationId;
  final double width;
  final double height;

  /// カード内にSNSのURLを出すか。ダイアログはカードの下にタップできる別要素で
  /// 出すためfalse、操作できないホバーカードはtrue。
  final bool showSnsLinks;

  /// 渡すと、カード内のURLをタップして開ける。
  final ValueChanged<SnsLink>? onOpenSnsLink;

  /// Rhing Seedの行をタップしてコピーできるようにするか（相手のカードを見るダイアログ用、
  /// 2026-10-31）。ホバーカードのように操作できない場所ではfalse。
  final bool copyRhingSeed;

  /// 誕生日は、カードを見る人の言語の並びで整形する（2026-10-23）。
  String? _birthdayLabel(BuildContext context) {
    final birthday = user.effectiveBirthdayFor(conversationId);
    if (birthday == null) return null;
    final locale = AppLocale.fromLanguageCode(
      Localizations.localeOf(context).languageCode,
    );
    return formatBirthday(birthday, locale);
  }

  @override
  Widget build(BuildContext context) {
    final card = user.profileCardFor(conversationId);
    final nickname = user.effectiveNicknameFor(conversationId);
    final name = (nickname?.text.isNotEmpty ?? false)
        ? nickname!.text
        : '@${user.rhingSeed}';
    // 呼び名が未設定で既に`@rhingSeed`を見出しに出している時は、重ねて出さない。
    final showSeedLine =
        user.effectiveShowRhingSeedFor(conversationId) &&
        user.rhingSeed.isNotEmpty &&
        (nickname?.text.isNotEmpty ?? false);
    return ProfileCardView(
      width: width,
      height: height,
      icon: user.effectiveIconFor(conversationId),
      background: user.effectiveBackgroundImageFor(conversationId),
      backgroundFocal: card?.backgroundFocal,
      iconFocal: card?.iconFocal,
      layoutPreset: card?.layoutPreset,
      textAlign: card?.textAlign,
      fontColor: card?.fontColor,
      nickname: name,
      statusMessage: user.effectiveStatusMessageFor(conversationId)?.text,
      birthdayLabel: _birthdayLabel(context),
      rhingSeedLabel: showSeedLine ? '@${user.rhingSeed}' : null,
      rhingSeedCopyText: showSeedLine && copyRhingSeed
          ? '@${user.rhingSeed}'
          : null,
      rhingSeedCopiedLabel: Strings.ofContext(context).webhookCopied,
      onOpenSnsLink: onOpenSnsLink,
      snsLinks: showSnsLinks
          ? user.effectiveSnsLinksFor(conversationId)
          : const [],
      fontFamily: user.effectiveFontDesignFor(conversationId)?.fontFamily,
    );
  }
}
