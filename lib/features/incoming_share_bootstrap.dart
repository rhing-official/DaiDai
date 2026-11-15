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

  Future<void> _handle(IncomingShare share) async {
    if (_busy || !mounted) return;
    _busy = true;
    final strings = ref.read(appStringsProvider);
    try {
      final target = await showForwardTargetDialog(
        context,
        currentUserId: widget.currentUserId,
        preview: ForwardPreview(
          text: share.text,
          files: [for (final f in share.files) f.name],
        ),
      );
      if (target == null || !mounted) return;
      showAutoDismissBanner(context, message: strings.forwardSending);
      await _send(share, target);
      if (mounted) {
        showAutoDismissBanner(context, message: strings.forwardDone);
      }
    } catch (e, st) {
      debugPrint('[incomingShare] send failed: $e\n$st');
      if (mounted) {
        showAutoDismissBanner(context, message: strings.forwardFailed);
      }
    } finally {
      _busy = false;
    }
  }

  Future<void> _send(IncomingShare share, ForwardTarget target) async {
    final me = await ref
        .read(userRepositoryProvider)
        .getUser(widget.currentUserId);
    final seed = me?.rhingSeed ?? '';
    final isDm = target.kind == ForwardTargetKind.dm;
    final text = share.text?.trim() ?? '';
    // 添付が1件だけなら、文字はその添付の本文として一緒に送る。
    final captionOnSingle = share.files.length == 1 && text.isNotEmpty;
    if (text.isNotEmpty && !captionOnSingle) {
      if (isDm) {
        await ref
            .read(directMessageRepositoryProvider)
            .sendTextMessage(
              dmId: target.conversationId,
              roomId: target.roomId,
              senderId: widget.currentUserId,
              senderRhingSeed: seed,
              content: text,
            );
      } else {
        await ref
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
      await forwardBytes(
        ref: ref,
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
