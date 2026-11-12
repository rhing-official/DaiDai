import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 着信通知（Androidの通話の着信通知）の「応答」で開かれた時の、まだ処理していない応答
/// （2026-11-12）。一対の通話は、着信のバナー（`IncomingCallBannerOverlay`）が現れ次第
/// 自動で応答し、広場の通話は、`GroupIncomingCallListener`が参加する。
class PendingCallAnswer {
  const PendingCallAnswer({
    required this.kind,
    required this.callId,
    this.groupId,
  });

  /// `dm`（一対）または`group`（広場）。
  final String kind;
  final String callId;
  final String? groupId;

  bool get isGroup => kind == 'group';
}

class PendingCallAnswerNotifier extends Notifier<PendingCallAnswer?> {
  @override
  PendingCallAnswer? build() => null;

  void set(PendingCallAnswer answer) => state = answer;

  void clear() => state = null;
}

final pendingCallAnswerProvider =
    NotifierProvider<PendingCallAnswerNotifier, PendingCallAnswer?>(
      PendingCallAnswerNotifier.new,
    );
