import 'dart:convert';

import 'app_user.dart';

/// `userInvites/{rhingSeed}`に保存する、個人の縁結び招待リンクの公開プレビュー。
/// 外部SNSのリンク展開（OGP）に見せるための最小限の情報のみを持つ
/// （友達一覧・語らいの内容などは一切含まない）。蔵のアイコン・呼び名・
/// アクティブな工房カードが変わるたびに同期して書き込む。
class UserInvitePreview {
  const UserInvitePreview({
    required this.userId,
    this.nickname,
    this.iconUrl,
    this.statusMessage,
    this.backgroundImageUrl,
    this.snsLinkUrls = const [],
    this.layoutPreset,
    this.textAlign,
    this.fontColorArgb,
    this.linkSalt,
  });

  final String userId;
  final String? nickname;
  final String? iconUrl;
  final String? statusMessage;

  /// OGP画像を工房のプロフィールカードそのままの見た目で生成するために使う
  /// （`api/og-image.js`が参照する）。アクティブな工房カードの`backgroundImageId`・
  /// `snsLinkIds`から解決した値。カード未選択時はnull/空のまま。
  final String? backgroundImageUrl;
  final List<String> snsLinkUrls;

  /// アクティブな工房カードの配置プリセットと文字の揃え（`CardLayoutPreset.name`
  /// /`CardTextAlign.name`、2026-10-12追加）。nullなら従来の左下・左揃え。
  final String? layoutPreset;
  final String? textAlign;

  /// アクティブな工房カードの文字色（ARGB、2026-10-31追加）。nullなら従来どおり。
  final int? fontColorArgb;

  /// 招待リンクの版識別子にだけ混ぜる値（Firestoreには保存しない）。
  /// `AppUser.inviteLinkSalt`。
  final int? linkSalt;

  /// [user]の現在のアクティブなカード等から作る公開プレビュー
  /// （`UserRepository.syncInvitePreview`の書き込み内容と、招待リンクの
  /// [version]の算出で共通に使う）。
  factory UserInvitePreview.fromUser(AppUser user) {
    return UserInvitePreview(
      userId: user.userId,
      nickname: user.effectiveNickname?.text,
      iconUrl: user.effectiveIcon?.url,
      statusMessage: user.effectiveStatusMessage?.text,
      backgroundImageUrl: user.effectiveBackgroundImage?.url,
      snsLinkUrls: [for (final link in user.effectiveSnsLinks) link.url],
      layoutPreset: user.activeProfileCard?.layoutPreset?.name,
      textAlign: user.activeProfileCard?.textAlign?.name,
      fontColorArgb: user.activeProfileCard?.fontColorArgb,
      linkSalt: user.inviteLinkSalt,
    );
  }

  /// 内容から決まる短い版識別子（FNV-1aの32bitを16進で）。招待リンクの末尾
  /// （`/invite/{seed}/{version}`）とOGP画像のURLに付け、カードを変えるとURLが
  /// 変わるようにする。DiscordやLINEなど外部アプリはリンク・画像のURL単位で
  /// プレビューを長時間キャッシュするため、URLが固定だと古いカードが出続ける
  /// （2026-10-13）。端末によらず同じ値になるよう、文字列のUTF-8バイトから自前で算出する。
  String get version {
    var hash = 0x811c9dc5;
    for (final byte in utf8.encode(jsonEncode([toJson(), linkSalt]))) {
      hash ^= byte;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  factory UserInvitePreview.fromJson(Map<String, dynamic> json) {
    return UserInvitePreview(
      userId: json['userId'] as String,
      nickname: json['nickname'] as String?,
      iconUrl: json['iconUrl'] as String?,
      statusMessage: json['statusMessage'] as String?,
      backgroundImageUrl: json['backgroundImageUrl'] as String?,
      snsLinkUrls: (json['snsLinkUrls'] as List?)?.cast<String>() ?? const [],
      layoutPreset: json['layoutPreset'] as String?,
      textAlign: json['textAlign'] as String?,
      fontColorArgb: json['fontColor'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'nickname': nickname,
      'iconUrl': iconUrl,
      'statusMessage': statusMessage,
      'backgroundImageUrl': backgroundImageUrl,
      'snsLinkUrls': snsLinkUrls,
      if (layoutPreset != null) 'layoutPreset': layoutPreset,
      if (textAlign != null) 'textAlign': textAlign,
      if (fontColorArgb != null) 'fontColor': fontColorArgb,
    };
  }
}
