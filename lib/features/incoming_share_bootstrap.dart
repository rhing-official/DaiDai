import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../l10n/strings.dart';
import '../providers/repository_providers.dart';
import '../services/incoming_share.dart';
import '../utils/auto_dismiss_banner.dart';
import '../utils/forward_message.dart';
import 'chat/forward_target_dialog.dart';

/// OSの共有メニューから渡された内容（文字・画像・動画・ファイル）を受け取り、送り先
/// （一対・広場の寄合）を選ばせて、新しいメッセージとして送る（2026-11-15）。送り先の
/// 選択は転送と同じポップアップを使う。HomeScreenの上位でラップして使う。
class IncomingShareBootstrap extends ConsumerStatefulWidget {
  const IncomingShareBootstrap({
    required this.currentUserId,
    required this.child,
    super.key,
  });

  final String currentUserId;
  final Widget child;

  @override
  ConsumerState<IncomingShareBootstrap> createState() =>
      _IncomingShareBootstrapState();
}

class _IncomingShareBootstrapState
    extends ConsumerState<IncomingShareBootstrap> {
  final _service = IncomingShareService();
  StreamSubscription<IncomingShare>? _sub;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (!_service.supported) return;
    _sub = _service.stream().listen(_handle);
    _service.initial().then((share) {
      if (share == null || share.isEmpty) return;
      // Webは共有の引数がURLに残るため、再読込で何度も出ないよう外す。
      if (kIsWeb && mounted) GoRouter.maybeOf(context)?.go('/');
      _handle(share);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  /// バナーを出す。画面（Overlay）が既に無い・失敗した時も、送信そのものは止めない。
  void _banner(OverlayState? overlay, String message) {
    if (overlay == null || !overlay.mounted) return;
    try {
      showAutoDismissBannerIn(overlay, message: message);
    } catch (e) {
      debugPrint('[incomingShare] banner failed: $e');
    }
  }

  Future<void> _handle(IncomingShare share) async {
    if (_busy || !mounted) {
      debugPrint('[incomingShare] skipped busy=$_busy mounted=$mounted');
      return;
    }
    _busy = true;
    // ポップアップを閉じたあとに、この画面が作り直されて破棄されても送れるよう、使う物を
    // 先に取っておく（破棄後の`ref.read`・`context`は例外になり、黙って送られなくなる）。
    final container = ProviderScope.containerOf(context);
    final overlay = Overlay.maybeOf(context);
    final strings = ref.read(appStringsProvider);
    debugPrint(
      '[incomingShare] received text=${share.text != null} '
      'files=${share.files.length}',
    );
    try {
      ForwardTarget? picked;
      final result = await showForwardTargetDialog(
        context,
        onPicked: (t) => picked = t,
        currentUserId: widget.currentUserId,
        preview: ForwardPreview(
          text: share.text,
          files: [for (final f in share.files) f.name],
        ),
      );
      // ポップアップの戻り値が届かなくても、確定時に受け取った転送先で送る。
      final target = result ?? picked;
      if (target == null) {
        debugPrint('[incomingShare] cancelled (no target)');
        return;
      }
      if (result == null) {
        debugPrint('[incomingShare] dialog result was null; using picked');
      }
      debugPrint(
        '[incomingShare] target kind=${target.kind} '
        'conversation=${target.conversationId} room=${target.roomId} '
        'mounted=$mounted',
      );
      _banner(overlay, strings.forwardSending);
      await _send(container, share, target);
      debugPrint('[incomingShare] sent');
      _banner(overlay, strings.forwardDone);
    } catch (e, st) {
      debugPrint('[incomingShare] send failed: $e\n$st');
      _banner(overlay, strings.forwardFailed);
    } finally {
      _busy = false;
    }
  }

  Future<void> _send(
    ProviderContainer container,
    IncomingShare share,
    ForwardTarget target,
  ) async {
    final me = await container
        .read(userRepositoryProvider)
        .getUser(widget.currentUserId);
    final seed = me?.rhingSeed ?? '';
    final isDm = target.kind == ForwardTargetKind.dm;
    final text = share.text?.trim() ?? '';
    // 添付が1件だけなら、文字はその添付の本文として一緒に送る。
    final captionOnSingle = share.files.length == 1 && text.isNotEmpty;
    if (text.isNotEmpty && !captionOnSingle) {
      if (isDm) {
        await container
            .read(directMessageRepositoryProvider)
            .sendTextMessage(
              dmId: target.conversationId,
              roomId: target.roomId,
              senderId: widget.currentUserId,
              senderRhingSeed: seed,
              content: text,
            );
      } else {
        await container
            .read(groupRepositoryProvider)
            .sendRoomMessage(
              groupId: target.conversationId,
              roomId: target.roomId,
              senderId: widget.currentUserId,
              senderRhingSeed: seed,
              content: text,
            );
      }
    }
    for (final file in share.files) {
      final bytes = await File(file.path).readAsBytes();
      await forwardBytesVia(
        container: container,
        bytes: bytes,
        fileName: file.name,
        contentType: file.contentType,
        target: target,
        senderId: widget.currentUserId,
        senderRhingSeed: seed,
        caption: captionOnSingle ? text : null,
      );
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
