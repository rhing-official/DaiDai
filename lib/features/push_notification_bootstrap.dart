import 'dart:io' show Platform;

import 'package:collection/collection.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/account_switcher_providers.dart';
import '../providers/call_answer_providers.dart';
import 'call/active_call_session.dart';
import 'call/pinned_call_overlay.dart' show reopenActiveCall;
import '../providers/locked_call_providers.dart';
import '../providers/repository_providers.dart';
import '../providers/ring_launch_provider.dart';
import '../push_notifications.dart';
import '../utils/auto_dismiss_banner.dart';
import '../utils/notification_target.dart';
import '../repositories/switch_session_repository.dart';
import '../l10n/strings.dart';
import 'call/call_log.dart';
import 'settings/account_toggle.dart' show switchAccountFailureMessage;

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
    signedInAccountId = widget.currentUserId;
    publishCurrentAccountId(widget.currentUserId);
    pendingNotificationTarget.addListener(_onPendingTarget);
    _maybeAutoRequest();
    _listenCallAnswers();
    WidgetsBinding.instance.addPostFrameCallback((_) => _resumeTargets());
  }

  @override
  void dispose() {
    pendingNotificationTarget.removeListener(_onPendingTarget);
    if (signedInAccountId == widget.currentUserId) signedInAccountId = null;
    super.dispose();
  }

  // 使っていないアカウント宛ての通知・着信（2026-11-24、`notification_target.dart`）。

  /// 起動した時に、切り替えの前後で引き継いだ行き先と、起動直後に溜まっていた行き先を処理する。
  Future<void> _resumeTargets() async {
    final saved = await takeSavedNotificationTarget(
      DateTime.now().millisecondsSinceEpoch,
    );
    if (saved != null && saved.recipientId == widget.currentUserId) {
      callLog('account switch: resumed ${saved.kind.name}');
      // 切り替えでアプリが作り直された直後。画面（ルーター）が落ち着くのを待ってから開く。
      await Future<void>.delayed(const Duration(milliseconds: 400));
      if (mounted) await _perform(saved);
    } else if (accountSwitchBusy.value &&
        pendingNotificationTarget.value == null) {
      // 起動時に出したスケルトン（期限切れ・宛先違い・行き先なし）を閉じる。
      callLog(
        'account switch: no target to resume (saved=${saved?.recipientId} '
        'current=${widget.currentUserId})',
      );
      accountSwitchBusy.value = false;
    }
    _onPendingTarget();
  }

  void _showBanner(String message) {
    final overlay = Overlay.maybeOf(context);
    if (overlay != null) showAutoDismissBannerIn(overlay, message: message);
  }

  void _onPendingTarget() {
    final target = pendingNotificationTarget.value;
    if (target == null || !mounted) return;
    pendingNotificationTarget.value = null;
    if (target.isExpired(DateTime.now().millisecondsSinceEpoch)) {
      callLog('account switch: target expired');
      accountSwitchBusy.value = false;
      return;
    }
    if (target.recipientId == widget.currentUserId) {
      _perform(target);
    } else {
      accountSwitchBusy.value = true;
      _switchFor(target);
    }
  }

  /// 切り替えを再試行してよい失敗か。通信の一時的な失敗は再試行し、合言葉の失効・極みの
  /// 契約切れ・上限は、繰り返しても直らないのですぐ失敗にする。
  static bool _retryable(Object error) =>
      error is! SwitchAccountException ||
      error.kind == SwitchAccountFailure.other;

  /// 宛先のアカウントへ切り替える。切り替えでアプリが作り直されるので、行き先を保存して
  /// 引き継ぐ。宛先のアカウントがこの端末に保存されていない・切り替えに失敗した時は、
  /// 従来どおりの動き（[_fallback]）にする。
  Future<void> _switchFor(NotificationTarget target) async {
    final switcher = ref.read(accountSwitcherProvider);
    final accounts = await switcher.accounts();
    final account = accounts.firstWhereOrNull(
      (a) => a.uid == target.recipientId,
    );
    if (account == null) {
      callLog('account switch: account not saved on this device');
      accountSwitchBusy.value = false;
      _fallback(target);
      return;
    }
    accountSwitchBusy.value = true;
    final strings = ref.read(appStringsProvider);
    final overlay = Overlay.maybeOf(context);
    await savePendingNotificationTarget(target);
    Object? lastError;
    for (var attempt = 1; attempt <= 3; attempt++) {
      try {
        callLog('account switch: attempt $attempt');
        await switcher.switchTo(account);
        // 成功すると、アプリが作り直される（Webは再読み込み）。ここへは戻らないことが多い。
        return;
      } catch (error) {
        lastError = error;
        callLog('account switch: attempt $attempt failed: $error');
        if (!_retryable(error) || attempt == 3) break;
        await Future<void>.delayed(Duration(seconds: attempt));
        // 待つ間にこの画面が外れても、切り替え自体は続けて完了させる。
      }
    }
    await takeSavedNotificationTarget(DateTime.now().millisecondsSinceEpoch);
    accountSwitchBusy.value = false;
    final message = lastError is SwitchAccountException
        ? switchAccountFailureMessage(
            strings,
            lastError,
            fallback: strings.switchAccountsFailed,
          )
        : strings.switchAccountsFailed;
    if (overlay != null && overlay.mounted) {
      showAutoDismissBannerIn(overlay, message: message);
    }
    _fallback(target);
  }

  /// 宛先が今のアカウントの時の動き。
  Future<void> _perform(NotificationTarget target) async {
    switch (target.kind) {
      case NotificationTargetKind.chat:
        navigateFromNotificationPayload(
          target.data['payload'] as String?,
          skipAccountCheck: true,
        );
        accountSwitchBusy.value = false;
      case NotificationTargetKind.callAnswer:
        final callId = target.data['callId'] as String?;
        _setPendingAnswer(
          kind: target.data['kind'] as String? ?? 'dm',
          callId: callId,
          groupId: target.data['groupId'] as String?,
        );
        await _awaitAnswerConsumed(callId);
    }
  }

  /// 応答の指示が、通話のセッション（一対のバナー・広場のリスナー）に受け取られるのを待つ。
  /// 約12秒たっても受け取られなければ（通話が既に終わった・読み込みが遅い）、指示を消して
  /// 知らせる。黙って終わらない（2026-11-25）。
  Future<void> _awaitAnswerConsumed(String? callId) async {
    final deadline = DateTime.now().add(const Duration(seconds: 12));
    while (mounted && DateTime.now().isBefore(deadline)) {
      if (ref.read(pendingCallAnswerProvider)?.callId != callId) {
        callLog('account switch: answer taken callId=$callId');
        accountSwitchBusy.value = false;
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    if (!mounted) return;
    callLog('account switch: answer not taken callId=$callId');
    ref.read(pendingCallAnswerProvider.notifier).clear();
    accountSwitchBusy.value = false;
    _showBanner(ref.read(appStringsProvider).switchAccountsCallNotEntered);
  }

  /// 切り替えられなかった時。語らいは従来どおり開こうとする（今のアカウントが参加者でなければ
  /// ホームに戻る）。着信の応答は、通話に入れないので何もしない。
  void _fallback(NotificationTarget target) {
    if (target.kind == NotificationTargetKind.chat) {
      navigateFromNotificationPayload(
        target.data['payload'] as String?,
        skipAccountCheck: true,
      );
    }
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
      if (call.method == 'ringLaunch') _setRingLaunch(call.arguments);
      if (call.method == 'openCall') _openCall();
      if (call.method == 'lockedBackUnlocked' && mounted) {
        ref.read(lockedBackUnlockedProvider.notifier).bump();
      }
    });
    try {
      // 起動時に溜まっている分。着信の全画面インテント由来の情報は、通話のセッションが始まる前に
      // 全画面の応答/拒否を出すために、先に受け取る（2026-11-18）。
      _setRingLaunch(await _callActionChannel.invokeMethod('takePendingRing'));
      _setAnswer(await _callActionChannel.invokeMethod('takePendingAction'));
    } on MissingPluginException {
      // 想定外の環境。何もしない。
    }
  }

  /// 通話中の通知のタップ。ミニ表示中の通話を、今の画面の上に通話画面として開く（2026-11-18）。
  void _openCall() {
    if (!mounted) return;
    final session = ref.read(activeCallSessionProvider);
    if (shouldReopenCallFromNotification(session)) {
      reopenActiveCall(ref.read, session!);
    }
  }

  void _setRingLaunch(Object? arguments) {
    if (!mounted) return;
    final ring = RingLaunch.fromChannel(arguments);
    if (ring != null) ref.read(ringLaunchProvider.notifier).set(ring);
  }

  void _setAnswer(Object? arguments) {
    if (!mounted || arguments is! Map) return;
    final callId = arguments['callId'] as String?;
    if (callId == null || callId.isEmpty) return;
    final kind = arguments['kind'] as String? ?? 'dm';
    final groupId = arguments['groupId'] as String?;
    // 使っていないアカウント宛ての着信は、宛先へ切り替えてから応答する（2026-11-24）。
    final recipientId = arguments['recipientId'] as String?;
    if (needsAccountSwitch(recipientId, widget.currentUserId)) {
      pendingNotificationTarget.value = NotificationTarget(
        kind: NotificationTargetKind.callAnswer,
        recipientId: recipientId!,
        data: {'kind': kind, 'callId': callId, 'groupId': groupId},
        createdAtMs: DateTime.now().millisecondsSinceEpoch,
      );
      return;
    }
    _setPendingAnswer(kind: kind, callId: callId, groupId: groupId);
  }

  void _setPendingAnswer({
    required String kind,
    required String? callId,
    required String? groupId,
  }) {
    if (!mounted || callId == null || callId.isEmpty) return;
    ref
        .read(pendingCallAnswerProvider.notifier)
        .set(PendingCallAnswer(kind: kind, callId: callId, groupId: groupId));
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
    // 取得を待つ間にサインアウト（アカウントの追加・切り替え）で画面が外れると、`ref`を使えず
    // `Using "ref" when a widget is about to or has been unmounted`になる（2026-11-24）。
    if (!mounted) return;
    await ref
        .read(pushNotificationRepositoryProvider)
        .requestPermissionAndRegister(widget.currentUserId);
  }

  Future<void> _carryOverMuted() async {
    try {
      final muted = await ref
          .read(accountSwitcherProvider)
          .isNotificationsMuted(widget.currentUserId);
      if (!muted || !mounted) return;
      await ref
          .read(pushNotificationRepositoryProvider)
          .setCurrentDeviceMuted(widget.currentUserId, true);
    } on Object catch (e) {
      if (kDebugMode) debugPrint('[DIAG-PUSH] carry over muted failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // トークン更新の追従（購読を開始するだけで良く、値自体は使わない）。
    // トークンが新しくなったら、この端末で通知を止めている印（`muted`）を新しいトークンへ
    // 引き継ぐ（2026-11-27）。印は端末のトークンに付くので、そのままだと止めていたのに
    // 再び届いてしまう。写し（保存したアカウント）が止めている時だけ付け直す。
    ref.listen(_fcmTokenRefreshProvider(widget.currentUserId), (_, next) {
      if (next.asData?.value == null) return;
      _carryOverMuted();
    });
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
