import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_locale_provider.dart';
import 'app_locale.dart';

/// DaiDai独自の世界観用語（蔵・工房・一対・広場…）の対訳。
/// 以前は[AppLocale]（日本語／English）に加え、利便性重視の言い換え
/// スタイルとの2軸（4通り）を持っていたが、「言語・用語設定によって
/// ブロックの大きさが変わり、全画面での対応が困難になった」ため
/// 2026-08-13に世界観重視の用語へ一本化し、[AppLocale]のみの1軸にした
/// （`docs/マップ.md`の対訳表のうち世界観重視の列を採用）。
class Vocabulary {
  const Vocabulary._({
    required this.dm,
    required this.plaza,
    required this.publicPlaza,
    required this.privatePlaza,
    required this.profileStorage,
    required this.profileCreator,
    required this.textChannel,
    required this.privateChannel,
    required this.category,
    required this.privateCategory,
    required this.projectBoard,
    required this.nickname,
    required this.statusMessage,
    required this.friendConnect,
    required this.owner,
    required this.sticker,
  });

  /// 1対1のチャット（一対／Private）。
  final String dm;

  /// サーバー全体の場（広場／Plaza）。
  final String plaza;

  /// 不特定多数のサーバー（表広場／Public Plaza）。
  final String publicPlaza;

  /// 友人のみのサーバー（裏広場／Private Plaza）。
  final String privatePlaza;

  /// プロフィールの保存庫（蔵／Wardrobe）。
  final String profileStorage;

  /// 複数プロフィールの作成画面（工房／Assembly Studio）。
  final String profileCreator;

  /// 通常のチャット（寄合／Text Channel）。
  final String textChannel;

  /// 非公開チャット（密談／Secret Council）。
  final String privateChannel;

  /// 通常のカテゴリ（表組／Public District）。
  final String category;

  /// 非公開カテゴリ（裏組／Private District）。
  final String privateCategory;

  /// 目的達成・進行型のフォーラム（談論／Milestone Board）。
  final String projectBoard;

  /// 友達に表示する呼び名（呼び名／ニックネーム、Englishは共通でNickname）。
  final String nickname;

  /// ひとことのステータス表示（一言／ステータスメッセージ、Englishは共通）。
  final String statusMessage;

  /// 招待リンク・QRコードで仲間を追加する画面（縁結び／Bond Shrine）。
  final String friendConnect;

  /// 広場の管理者（長／Chief）。
  final String owner;

  /// スタンプ機能（ペタピタ／Englishは共通でSticker）。
  final String sticker;

  static const japanese = Vocabulary._(
    dm: '一対',
    plaza: '広場',
    publicPlaza: '表広場',
    privatePlaza: '裏広場',
    profileStorage: '蔵',
    profileCreator: '工房',
    textChannel: '寄合',
    privateChannel: '密談',
    category: '表組',
    privateCategory: '裏組',
    projectBoard: '談論',
    nickname: '呼び名',
    statusMessage: '一言',
    friendConnect: '縁結び',
    owner: '長',
    sticker: 'ペタピタ',
  );

  static const english = Vocabulary._(
    dm: 'Private',
    plaza: 'Plaza',
    publicPlaza: 'Public Plaza',
    privatePlaza: 'Private Plaza',
    profileStorage: 'Wardrobe',
    profileCreator: 'Assembly Studio',
    textChannel: 'Text Channel',
    privateChannel: 'Secret Council',
    category: 'Public District',
    privateCategory: 'Private District',
    projectBoard: 'Milestone Board',
    nickname: 'Nickname',
    statusMessage: 'Status message',
    friendConnect: 'Bond Shrine',
    owner: 'Chief',
    sticker: 'Sticker',
  );

  static Vocabulary of(AppLocale locale) {
    return switch (locale) {
      AppLocale.japanese => japanese,
      AppLocale.britishEnglish => english,
    };
  }
}

/// 現在の表示言語に対応するDaiDai語彙（世界観重視の用語で固定）。
final vocabularyProvider = Provider<Vocabulary>((ref) {
  final locale = ref.watch(appLocaleProvider);
  return Vocabulary.of(locale);
});
