import 'dart:io' show Platform;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/call_answer_providers.dart';
import '../providers/repository_providers.dart';
import '../push_notifications.dart';

/// ログイン済みユーザーが判明した時点で、プッシュ通知の権限リクエスト・
/// FCMトークン登録・トークン更新の追従・フォアグラウンド受信時の
/// ローカル通知表示（Android）をまとめて行う（[IncomingCallListener]と
/// 同様、`AppGate`でHomeScreenの上位をラップして使う、2026-08-31追加）。
class PushNotificationBootstrap extends ConsumerStatefulWidget {
  const PushNotificationBootstrap({
    required this.currentUserId,
    required this.child,
    super.key,
  });

  final String currentUserId;
  final Widget child;

  @override
  ConsumerState<PushNotificationBootstrap> createState() =>
      _PushNotificationBootstrapState();
}

class _PushNotificationBootstrapState
    extends ConsumerState<PushNotificationBootstrap> {
  @override
  void initState() {
    super.initState();
    _maybeAutoRequest();
    _listenCallAnswers();
  }

  /// Androidの着信通知（CallStyle）の「応答」で開かれた時の応答を受け取る（2026-11-12）。
  /// 起動時に溜まっている分と、開いている間に届く分の両方。
  static const _callActionChannel = MethodChannel(
    'jp.rhing.daidai/call_action',
  );

  Future<void> _listenCallAnswers() async {
    if (kIsWeb || !Platform.isAndroid) return;
    _callActionChannel.setMethodCallHandler((call) async {
      if (call.method == 'answer') _setAnswer(call.arguments);
    });
    try {
      _setAnswer(await _callActionChannel.invokeMethod('takePendingAction'));
    } on MissingPluginException {
      // 想定外の環境。何もしない。
    }
  }

  void _setAnswer(Object? arguments) {
    if (!mounted || arguments is! Map) return;
    final callId = arguments['callId'] as String?;
    if (callId == null || callId.isEmpty) return;
    ref
        .read(pendingCallAnswerProvider.notifier)
        .set(
          PendingCallAnswer(
            kind: arguments['kind'] as String? ?? 'dm',
            callId: callId,
            groupId: arguments['groupId'] as String?,
          ),
        );
  }

  /// 設定タブのトグルで明示的にオフにされていた場合（[AppUser.
  /// pushNotificationsEnabled] == false）は、起動のたびに自動で許可を
  /// リクエストし直さない（2026-09-01追加。null＝未設定の既存/新規ユーザーは
  /// 従来通り自動リクエストする、オンボーディング体験は変えない）。
  Future<void> _maybeAutoRequest() async {
    final user = await ref
        .read(userRepositoryProvider)
        .getUser(widget.currentUserId);
    if (kDebugMode) {
      debugPrint(
        '[DIAG-PUSH] bootstrap pushNotificationsEnabled='
        '${user?.pushNotificationsEnabled}',
      );
    }
    if (user?.pushNotificationsEnabled == false) return;
    await ref
        .read(pushNotificationRepositoryProvider)
        .requestPermissionAndRegister(widget.currentUserId);
  }

  @override
  Widget build(BuildContext context) {
    // トークン更新の追従（購読を開始するだけで良く、値自体は使わない）。
    ref.listen(_fcmTokenRefreshProvider(widget.currentUserId), (_, _) {});
    // フォアグラウンド受信時はOSが自動表示しない為、Android向けに
    // 自前でローカル通知を出す（Webはshow側でno-op、push_notifications.dart参照）。
    ref.listen(_fcmForegroundMessageProvider, (previous, next) {
      final message = next.asData?.value;
      if (kDebugMode && message != null) {
        debugPrint('[DIAG-PUSH] onMessage data=${message.data.keys.toList()}');
      }
      if (message != null) showRemoteMessageNotification(message);
    });
    return widget.child;
  }
}

final _fcmTokenRefreshProvider = StreamProvider.family((ref, String userId) {
  return ref.watch(pushNotificationRepositoryProvider).onTokenRefresh(userId);
});

final _fcmForegroundMessageProvider = StreamProvider((ref) {
  return FirebaseMessaging.onMessage;
});
