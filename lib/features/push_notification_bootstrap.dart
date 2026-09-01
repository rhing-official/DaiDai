import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  }

  /// 設定タブのトグルで明示的にオフにされていた場合（[AppUser.
  /// pushNotificationsEnabled] == false）は、起動のたびに自動で許可を
  /// リクエストし直さない（2026-09-01追加。null＝未設定の既存/新規ユーザーは
  /// 従来通り自動リクエストする、オンボーディング体験は変えない）。
  Future<void> _maybeAutoRequest() async {
    final user = await ref
        .read(userRepositoryProvider)
        .getUser(widget.currentUserId);
    if (user?.pushNotificationsEnabled == false) return;
    await ref
        .read(pushNotificationRepositoryProvider)
        .requestPermissionAndRegister(widget.currentUserId);
  }

  @override
  Widget build(BuildContext context) {
    // トークン更新の追従（購読を開始するだけで良く、値自体は使わない）。
    ref.listen(_fcmTokenRefreshProvider(widget.currentUserId), (_, _) {});
    // フォアグラウンド受信時はOSが自動表示しないため、Android向けに
    // 自前でローカル通知を出す（Webはshow側でno-op、push_notifications.dart参照）。
    ref.listen(_fcmForegroundMessageProvider, (previous, next) {
      final message = next.asData?.value;
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
