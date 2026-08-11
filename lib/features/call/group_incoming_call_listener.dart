import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/app_user.dart';
import '../../models/group_call.dart';
import '../../providers/group_call_providers.dart';
import '../../providers/repository_providers.dart';
import '../../router/app_router.dart';
import 'call_sound_player.dart';

/// アプリ全体で、自分がメンバーになっている広場の新規通話開始を監視し、
/// バナー表示＋着信音（3コールのみ）で知らせる。1対1の[IncomingCallListener]と
/// 異なり、グループ通話は「進行中の通話に途中から参加する」プル型設計で
/// 着信の概念自体が無いため、フルスクリーンの着信画面には遷移させず、
/// バナーをタップした時だけ確認無しでそのまま通話に参加する。
/// HomeScreenの上位でIncomingCallListenerと並べてラップして使う。
class GroupIncomingCallListener extends ConsumerStatefulWidget {
  const GroupIncomingCallListener({
    required this.currentUser,
    required this.child,
    super.key,
  });

  final AppUser currentUser;
  final Widget child;

  @override
  ConsumerState<GroupIncomingCallListener> createState() =>
      _GroupIncomingCallListenerState();
}

class _GroupIncomingCallListenerState
    extends ConsumerState<GroupIncomingCallListener> {
  final _soundPlayer = CallSoundPlayer();
  final List<_PendingBanner> _banners = [];
  Set<String> _knownCallIds = {};
  bool _seeded = false;

  @override
  void dispose() {
    _soundPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(activeGroupCallsForUserProvider(widget.currentUser.userId), (
      previous,
      next,
    ) {
      final calls = next.asData?.value ?? const <GroupCall>[];
      final currentIds = calls.map((c) => c.groupCallId).toSet();

      // 初回スナップショットは、既に進行中だった通話を「新規開始」と
      // 誤検知しないよう無音でシードする
      // （webrtc_group_call_controller.dartの_hasReceivedFirstSnapshotと同じ考え方）。
      if (!_seeded) {
        _seeded = true;
        _knownCallIds = currentIds;
        return;
      }

      final newIds = currentIds.difference(_knownCallIds);
      _knownCallIds = currentIds;

      setState(() {
        _banners.removeWhere((b) => !currentIds.contains(b.call.groupCallId));
      });

      for (final call in calls) {
        if (!newIds.contains(call.groupCallId)) continue;
        if (call.initiatorId == widget.currentUser.userId) continue;
        _handleNewCall(call);
      }
    });

    return Stack(
      children: [
        widget.child,
        for (final banner in _banners)
          Positioned(
            top: MediaQuery.paddingOf(context).top + 8,
            left: 8,
            right: 8,
            child: _GroupCallBanner(
              groupName: banner.groupName,
              isVideo: banner.call.isVideo,
              onTap: () => _joinCall(banner.call),
              onDismiss: () => setState(
                () => _banners.removeWhere(
                  (b) => b.call.groupCallId == banner.call.groupCallId,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _handleNewCall(GroupCall call) async {
    final group = await ref
        .read(groupRepositoryProvider)
        .getGroup(call.groupId);
    if (!mounted) return;
    setState(() {
      _banners.add(_PendingBanner(call: call, groupName: group?.name ?? '広場'));
    });
    unawaited(_soundPlayer.playRingtoneTimes(3));
  }

  Future<void> _joinCall(GroupCall call) async {
    setState(
      () => _banners.removeWhere((b) => b.call.groupCallId == call.groupCallId),
    );

    final groupCallRepository = ref.read(groupCallRepositoryProvider);
    final participants = await groupCallRepository
        .watchParticipants(call.groupCallId)
        .first;
    if (participants.length >= call.maxParticipants) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('この通話は満員です（上限${call.maxParticipants}人）')),
        );
      }
      return;
    }

    if (!mounted) return;
    ref
        .read(goRouterProvider)
        .push(
          '/group-call',
          extra: GroupCallArgs(
            groupCallId: call.groupCallId,
            currentUser: widget.currentUser,
            isVideo: call.isVideo,
          ),
        );
  }
}

class _PendingBanner {
  const _PendingBanner({required this.call, required this.groupName});
  final GroupCall call;
  final String groupName;
}

class _GroupCallBanner extends StatelessWidget {
  const _GroupCallBanner({
    required this.groupName,
    required this.isVideo,
    required this.onTap,
    required this.onDismiss,
  });

  final String groupName;
  final bool isVideo;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(12),
      color: colorScheme.primaryContainer,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(
                isVideo ? Icons.videocam : Icons.call,
                color: colorScheme.onPrimaryContainer,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '$groupNameで通話が始まりました。タップして参加',
                  style: TextStyle(color: colorScheme.onPrimaryContainer),
                ),
              ),
              IconButton(
                icon: Icon(Icons.close, color: colorScheme.onPrimaryContainer),
                onPressed: onDismiss,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
