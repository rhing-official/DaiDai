import 'package:cloud_functions/cloud_functions.dart';

import '../l10n/strings.dart';

/// [FriendRepository.sendRequest]の失敗を、ユーザーに見せる文言に変換する
/// （2026-09-07追加）。`sendFriendRequest` Cloud Functionsが技術仕様書8.3
/// レイヤー1（送信頻度のレート制限）・レイヤー2（同一内容の大量送信検知）に
/// 該当すると`resource-exhausted`で拒否するため、その場合だけ専用の文言に
/// 差し替える。それ以外の失敗は既存の汎用エラー表示のまま。
String friendRequestErrorMessage(Object error, Strings strings) {
  if (error is FirebaseFunctionsException &&
      error.code == 'resource-exhausted') {
    return strings.friendRequestRateLimited;
  }
  return 'エラーが発生しました: $error';
}
