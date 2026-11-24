import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 通知・着信が「使っていないアカウント宛て」だった時に、宛先のアカウントへ切り替えてから
/// 開く仕組みの共通部分（2026-11-24、`文書/直近/複数アカウント.md`の段階2）。
///
/// 通知のタップ・着信の応答は、アプリの外（OSの通知）から来るため、`ref`を持たない場所で
/// 受け取る。ここでは「宛先が今のアカウントと違う」と分かった時に、行き先を
/// [pendingNotificationTarget]へ置く。`PushNotificationBootstrap`がそれを見て、保存済みの
/// アカウントへ[AccountSwitcher.switchTo]で切り替える。切り替えでアプリが作り直される
/// （Webは再読み込み）ため、行き先は端末に保存して引き継ぎ、切り替え後に開く。

/// 行き先の種類。
enum NotificationTargetKind {
  /// 通知をタップして、語らい（一対・広場の寄合）を開く。
  chat,

  /// 着信の「応答」。切り替え後に、その通話へ応答する。
  callAnswer,
}

/// 切り替えの待ち時間が長引いた時に、古い行き先で突然開かないための有効期間。
/// 着信は約30秒で鳴り止むので、それより十分に長い程度にする。
const kNotificationTargetTtl = Duration(minutes: 3);

/// 端末内の保存キー。アカウントごとの設定の入れ替え（`swapLocalStateTo`）の対象外にする
/// （`account_local_state.dart`の`_keepKeys`）。切り替えの前後で残さないと意味が無い。
const kPendingNotificationTargetKey = 'pendingNotificationTarget';

/// 今のアカウントのid。ネイティブ（Androidの着信通知）が、前面でも別アカウント宛ての着信を
/// 出すかを決めるために読む（`flutter.currentAccountId`）。入れ替えの対象外。
const kCurrentAccountIdKey = 'currentAccountId';

class NotificationTarget {
  const NotificationTarget({
    required this.kind,
    required this.recipientId,
    required this.data,
    required this.createdAtMs,
  });

  /// 宛先（通知を受け取るアカウント）のid。
  final String recipientId;
  final NotificationTargetKind kind;

  /// [NotificationTargetKind.chat]は`{'payload': 通知のpayload（JSON文字列）}`、
  /// [NotificationTargetKind.callAnswer]は`{'kind': 'dm'|'group', 'callId': ..., 'groupId': ...}`。
  final Map<String, dynamic> data;
  final int createdAtMs;

  bool isExpired(int nowMs) =>
      nowMs - createdAtMs > kNotificationTargetTtl.inMilliseconds;

  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    'recipientId': recipientId,
    'data': data,
    'createdAtMs': createdAtMs,
  };

  static NotificationTarget? tryFromJson(Object? json) {
    if (json is! Map) return null;
    final kindName = json['kind'];
    final recipientId = json['recipientId'];
    final data = json['data'];
    final createdAtMs = json['createdAtMs'];
    if (kindName is! String ||
        recipientId is! String ||
        recipientId.isEmpty ||
        data is! Map ||
        createdAtMs is! int) {
      return null;
    }
    final kind = NotificationTargetKind.values
        .where((k) => k.name == kindName)
        .firstOrNull;
    if (kind == null) return null;
    return NotificationTarget(
      kind: kind,
      recipientId: recipientId,
      data: Map<String, dynamic>.from(data),
      createdAtMs: createdAtMs,
    );
  }
}

/// 切り替えを待っている行き先。`PushNotificationBootstrap`が購読する。
final ValueNotifier<NotificationTarget?> pendingNotificationTarget =
    ValueNotifier<NotificationTarget?>(null);

/// 今サインインしているアカウントのid（`PushNotificationBootstrap`が設定する）。
/// まだ分からない間（起動直後）は`null`。
String? signedInAccountId;

/// 宛先[recipientId]が、今のアカウント[currentId]と違い、切り替えが要るか。
/// 宛先が無い（古い通知・古いサーバー）時は、従来どおり切り替えない。今のアカウントが
/// まだ分からない（`null`）時は、判断を`PushNotificationBootstrap`に任せるため`true`。
bool needsAccountSwitch(String? recipientId, String? currentId) =>
    recipientId != null && recipientId.isNotEmpty && currentId != recipientId;

/// 行き先を、切り替えの前後で残るよう端末に保存する。
Future<void> savePendingNotificationTarget(NotificationTarget target) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(
    kPendingNotificationTargetKey,
    jsonEncode(target.toJson()),
  );
}

/// 保存した行き先を取り出して消す。無い・壊れている・期限切れなら`null`。
Future<NotificationTarget?> takeSavedNotificationTarget(int nowMs) async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(kPendingNotificationTargetKey);
  if (raw == null) return null;
  await prefs.remove(kPendingNotificationTargetKey);
  try {
    final target = NotificationTarget.tryFromJson(jsonDecode(raw));
    if (target == null || target.isExpired(nowMs)) return null;
    return target;
  } on FormatException {
    return null;
  }
}

/// 今のアカウントのidを、ネイティブが読めるよう端末に書く。
Future<void> publishCurrentAccountId(String uid) async {
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getString(kCurrentAccountIdKey) == uid) return;
  await prefs.setString(kCurrentAccountIdKey, uid);
}
