import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 着信の全画面インテント（Androidの着信通知、スリープ・ロック中）でアプリが開かれた時の、
/// 着信の情報（2026-11-18）。Firestoreの着信の検知を待たずに、すぐ全画面の応答/拒否を出す
/// ために使う（待つ間、アプリの前回の画面が見えてしまっていた）。通知に載せた情報だけで出し、
/// 実際の通話のセッションが始まったら、そちらに引き継ぐ。
class RingLaunch {
  const RingLaunch({
    required this.kind,
    required this.callId,
    required this.callerName,
    required this.isVideo,
    this.groupId,
    this.iconUrl,
  });

  /// `dm`（一対）または`group`（広場）。
  final String kind;
  final String callId;
  final String? groupId;
  final String callerName;
  final String? iconUrl;
  final bool isVideo;

  bool get isGroup => kind == 'group';

  static RingLaunch? fromChannel(Object? arguments) {
    if (arguments is! Map) return null;
    final callId = arguments['callId'] as String?;
    if (callId == null || callId.isEmpty) return null;
    return RingLaunch(
      kind: arguments['kind'] as String? ?? 'dm',
      callId: callId,
      groupId: arguments['groupId'] as String?,
      callerName: arguments['callerName'] as String? ?? '',
      iconUrl: arguments['iconUrl'] as String?,
      isVideo: arguments['isVideo'] as bool? ?? false,
    );
  }
}

class RingLaunchNotifier extends Notifier<RingLaunch?> {
  @override
  RingLaunch? build() => null;

  void set(RingLaunch ring) => state = ring;

  void clear() => state = null;
}

final ringLaunchProvider = NotifierProvider<RingLaunchNotifier, RingLaunch?>(
  RingLaunchNotifier.new,
);
