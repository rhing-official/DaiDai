import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_locale_provider.dart';
import '../providers/terminology_style_provider.dart';
import 'app_locale.dart';
import 'terminology_style.dart';

/// DaiDai独自の世界観用語（蔵・工房・一対・広場…）の対訳。
/// `docs/マップ.md`の対訳表（言語×用語スタイルの2軸）をそのまま反映したもので、
/// [TerminologyStyle]（世界観重視／利便性重視）と[AppLocale]（日本語／English）の
/// 組み合わせ4通りぶんを保持する。
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
  });

  /// 1対1のチャット（一対／DM／ダイレクト／Private Chat）。
  final String dm;

  /// サーバー全体の場（広場／Server／サーバー／Plaza）。
  final String plaza;

  /// 不特定多数のサーバー（表広場／Public Server／公開サーバー／Public Plaza）。
  final String publicPlaza;

  /// 友人のみのサーバー（裏広場／Private Server／非公開サーバー／Private Plaza）。
  final String privatePlaza;

  /// プロフィールの保存庫（蔵／Material Box／マテリアルボックス／Wardrobe）。
  final String profileStorage;

  /// 複数プロフィールの作成画面（工房／Profile Card／プロフィール作成／Assembly Studio）。
  final String profileCreator;

  /// 通常のチャット（寄合／Chat Channel／チャンネル／Text Channel）。
  final String textChannel;

  /// 非公開チャット（密談／Private Channel／非公開チャンネル／Secret Council）。
  final String privateChannel;

  /// 通常のカテゴリ（表組／Category／カテゴリ／Public District）。
  final String category;

  /// 非公開カテゴリ（裏組／Private Category／非公開カテゴリ／Private District）。
  final String privateCategory;

  /// 目的達成・進行型のフォーラム（談論／Project Board／プロジェクトボード／Milestone Board）。
  final String projectBoard;

  /// 友達に表示する呼び名（呼び名／ニックネーム、Englishはスタイル問わず共通）。
  final String nickname;

  /// ひとことのステータス表示（一言／ステータスメッセージ、Englishはスタイル問わず共通）。
  final String statusMessage;

  /// 招待リンク・QRコードで仲間を追加する画面（縁結び／フレンド追加）。
  final String friendConnect;

  /// 広場の管理者（長／管理者）。
  final String owner;

  static const jaWorldview = Vocabulary._(
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
  );

  static const jaConvenience = Vocabulary._(
    dm: 'ダイレクト',
    plaza: 'サーバー',
    publicPlaza: '公開サーバー',
    privatePlaza: '非公開サーバー',
    profileStorage: 'マテリアルボックス',
    profileCreator: 'プロフィール作成',
    textChannel: 'チャンネル',
    privateChannel: '非公開チャンネル',
    category: 'カテゴリ',
    privateCategory: '非公開カテゴリ',
    projectBoard: 'プロジェクトボード',
    nickname: 'ニックネーム',
    statusMessage: 'ステータスメッセージ',
    friendConnect: 'フレンド追加',
    owner: '管理者',
  );

  static const enWorldview = Vocabulary._(
    dm: 'Private Chat',
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
  );

  static const enConvenience = Vocabulary._(
    dm: 'DM',
    plaza: 'Server',
    publicPlaza: 'Public Server',
    privatePlaza: 'Private Server',
    profileStorage: 'Material Box',
    profileCreator: 'Profile Card',
    textChannel: 'Chat Channel',
    privateChannel: 'Private Channel',
    category: 'Category',
    privateCategory: 'Private Category',
    projectBoard: 'Project Board',
    nickname: 'Nickname',
    statusMessage: 'Status message',
    friendConnect: 'Add Friends',
    owner: 'Owner',
  );

  static Vocabulary of(AppLocale locale, TerminologyStyle style) {
    return switch ((locale, style)) {
      (AppLocale.japanese, TerminologyStyle.worldview) => jaWorldview,
      (AppLocale.japanese, TerminologyStyle.convenience) => jaConvenience,
      (AppLocale.britishEnglish, TerminologyStyle.worldview) => enWorldview,
      (AppLocale.britishEnglish, TerminologyStyle.convenience) =>
        enConvenience,
    };
  }
}

/// 現在の表示言語・用語スタイルに対応するDaiDai語彙。
final vocabularyProvider = Provider<Vocabulary>((ref) {
  final locale = ref.watch(appLocaleProvider);
  final style = ref.watch(terminologyStyleProvider);
  return Vocabulary.of(locale, style);
});
