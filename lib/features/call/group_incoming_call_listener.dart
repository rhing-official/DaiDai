import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../../models/app_ui_style.dart';
import '../../models/app_user.dart';
import '../../models/group_call.dart';
import '../../models/sound_preset.dart';
import '../../providers/app_ui_style_provider.dart';
import '../../providers/group_call_providers.dart';
import '../../providers/repository_providers.dart';
import '../../providers/ringtone_sound_provider.dart';
import '../../router/app_router.dart';
import '../../utils/auto_dismiss_banner.dart';
import '../../theme/gekiga/gekiga_colors.dart';
import '../../utils/platform_info.dart';
import '../../widgets/glass/glass_surface.dart';
import '../../widgets/nav_chip.dart';
import 'active_call_session.dart';
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
  Set<String> _knownCallIds = {};
  bool _seeded = false;
  Timer? _errorBannerTimer;

  @override
  void initState() {
    super.initState();
    // バナー（最前面の[GroupCallBannerOverlay]）からの操作を受ける。
    // ビルド中にプロバイダーを書き換えないようフレーム後に登録する。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final notifier = ref.read(groupCallBannersProvider.notifier);
      notifier.onJoin = _joinCall;
      notifier.onDismissed = () => unawaited(_soundPlayer.stopRingtone());
    });
  }

  @override
  void dispose() {
    _soundPlayer.dispose();
    _errorBannerTimer?.cancel();
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

      final hadBanners = ref.read(groupCallBannersProvider).isNotEmpty;
      ref.read(groupCallBannersProvider.notifier).retainOnly(currentIds);
      // 通話が終わってバナーが消えたら、鳴りかけの着信音も止める。
      if (hadBanners && ref.read(groupCallBannersProvider).isEmpty) {
        unawaited(_soundPlayer.stopRingtone());
      }

      for (final call in calls) {
        if (!newIds.contains(call.groupCallId)) continue;
        if (call.initiatorId == widget.currentUser.userId) continue;
        _handleNewCall(call);
      }
    });

    return widget.child;
  }

  Future<void> _handleNewCall(GroupCall call) async {
    final group = await ref
        .read(groupRepositoryProvider)
        .getGroup(call.groupId);
    if (!mounted) return;
    ref
        .read(groupCallBannersProvider.notifier)
        .add(
          PendingGroupCallBanner(call: call, groupName: group?.name ?? '広場'),
        );
    final ringtoneSource = SoundCategory.ringtone.resolveSource(
      ref.read(ringtoneSoundProvider),
    );
    unawaited(_soundPlayer.playRingtoneTimes(3, ringtoneSource));
  }

  Future<void> _joinCall(GroupCall call) async {
    // 参加（応答）したら着信音を止める（2026-10-13、以前は3回鳴り終わるまで
    // 鳴り続けていた）。
    ref.read(groupCallBannersProvider.notifier).remove(call.groupCallId);
    unawaited(_soundPlayer.stopRingtone());

    final groupCallRepository = ref.read(groupCallRepositoryProvider);
    final participants = await groupCallRepository
        .watchParticipants(call.groupCallId)
        .first;
    if (participants.length >= call.maxParticipants) {
      if (mounted) {
        _errorBannerTimer = showAutoDismissBanner(
          context,
          message: 'この通話は満員です（上限${call.maxParticipants}人）',
          previousTimer: _errorBannerTimer,
        );
      }
      return;
    }

    if (!mounted) return;
    // モバイルのみ全画面の/group-callへpushする。PCでは全画面ルートを
    // 使わず、通話セッションを直接開始するだけにする（2026-08-19変更）。
    // その広場のメッセージ画面を開けば`EmbeddedCallPane`が埋め込み表示を
    // 出し、開いていない間は音声のみなら非表示・映像ありなら右上ピン留め
    // ミニ表示（`PinnedCallOverlay`）になる。
    if (isMobileCallPlatform) {
      ref
          .read(goRouterProvider)
          .push(
            '/group-call',
            extra: GroupCallArgs(
              groupCallId: call.groupCallId,
              groupId: call.groupId,
              currentUser: widget.currentUser,
              isVideo: call.isVideo,
            ),
          );
      return;
    }
    ref
        .read(activeCallSessionProvider.notifier)
        .startGroup(
          groupCallId: call.groupCallId,
          groupId: call.groupId,
          currentUser: widget.currentUser,
          isVideo: call.isVideo,
          groupCallRepository: groupCallRepository,
        );
  }
}

/// 参加を促すバナー1件（広場の通話の開始通知）。
class PendingGroupCallBanner {
  const PendingGroupCallBanner({required this.call, required this.groupName});
  final GroupCall call;
  final String groupName;
}

/// 表示中の広場通話バナー（2026-10-13）。描画は`main.dart`の最前面
/// （[GroupCallBannerOverlay]）で行い、検知・着信音・参加の処理は
/// [GroupIncomingCallListener]が行う。バナーが語らい一覧のルートの中にあると、
/// 別のルートやボタンの下に隠れてしまっていた。
class GroupCallBannersNotifier extends Notifier<List<PendingGroupCallBanner>> {
  @override
  List<PendingGroupCallBanner> build() => const [];

  void add(PendingGroupCallBanner banner) => state = [...state, banner];

  void remove(String groupCallId) => state = [
    for (final b in state)
      if (b.call.groupCallId != groupCallId) b,
  ];

  void retainOnly(Set<String> groupCallIds) => state = [
    for (final b in state)
      if (groupCallIds.contains(b.call.groupCallId)) b,
  ];

  /// バナーを押した時の参加処理（リスナーが登録）。
  void Function(GroupCall call)? onJoin;

  /// バナーを閉じた時の処理（リスナーが登録、着信音を止める）。
  void Function()? onDismissed;
}

final groupCallBannersProvider =
    NotifierProvider<GroupCallBannersNotifier, List<PendingGroupCallBanner>>(
      GroupCallBannersNotifier.new,
    );

/// 最前面に重ねる広場通話バナー。全ルート・ボタン・通話ミニ表示より上に出る。
/// 上スワイプ（または×）で閉じ、閉じたら着信音も止める。
class GroupCallBannerOverlay extends ConsumerWidget {
  const GroupCallBannerOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final banners = ref.watch(groupCallBannersProvider);
    if (banners.isEmpty) return const SizedBox.shrink();
    final notifier = ref.read(groupCallBannersProvider.notifier);
    final top = MediaQuery.paddingOf(context).top + 8;
    // コンピューターでは横いっぱいに広げず、左上に幅を絞って表示する
    // （2026-10-13）。スマホ・タブレットは従来どおり横幅いっぱい。
    final isComputer = classifyDevice(context) == DeviceClass.computer;
    return Positioned(
      top: top,
      // 左端のメニュー（ナビチップ）の列にかからないよう、その幅の分だけ右へ
      // ずらす（コンピューターのみ）。
      left: isComputer ? kNavChipSize + kNavChipMargin * 2 + 8 : 8,
      right: isComputer ? null : 8,
      width: isComputer ? 380 : null,
      child: PointerInterceptor(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final banner in banners)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Dismissible(
                  key: ValueKey('group-call-banner-${banner.call.groupCallId}'),
                  direction: DismissDirection.up,
                  onDismissed: (_) {
                    notifier.remove(banner.call.groupCallId);
                    notifier.onDismissed?.call();
                  },
                  child: _GroupCallBanner(
                    groupName: banner.groupName,
                    isVideo: banner.call.isVideo,
                    onTap: () => notifier.onJoin?.call(banner.call),
                    onDismiss: () {
                      notifier.remove(banner.call.groupCallId);
                      notifier.onDismissed?.call();
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 広場通話の参加バナーの見た目（3つのUIスタイル対応、2026-10-13）。
/// 色は`ChatTaskBanner`（`task_banner.dart`）と同じ規則: 劇画は固定の白黒
/// （有彩色なし）、フラット・ガラスはアクセントカラー（`colorScheme.primary`は
/// テーマ側で`accentColor`そのものに上書き済み）を地色にし、文字は`onPrimary`。
/// ガラスはその上にぼかし・半透明・縁の光彩だけを重ねる。影は使わない。
class _GroupCallBanner extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final uiStyle = ref.watch(appUiStyleProvider);
    final isGekiga = uiStyle == AppUiStyle.gekiga;
    final isGlass = uiStyle == AppUiStyle.glass;
    final background = isGekiga ? GekigaColors.panel : colorScheme.primary;
    final foreground = isGekiga ? GekigaColors.onPanel : colorScheme.onPrimary;
    final radius = isGekiga ? BorderRadius.zero : BorderRadius.circular(12);

    final content = InkWell(
      borderRadius: radius,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(isVideo ? Icons.videocam : Icons.call, color: foreground),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '$groupNameで通話が始まりました。\nタップして参加',
                style: TextStyle(color: foreground),
              ),
            ),
            IconButton(
              icon: Icon(Icons.close, color: foreground),
              onPressed: onDismiss,
            ),
          ],
        ),
      ),
    );

    if (isGlass) {
      // 塗りはフラットと同じアクセントカラー。ぼかし・半透明・縁の光彩は
      // `GlassSurface`が与える（他のガラスの浮遊カードと同じ光沢）。
      return GlassSurface(
        variant: GlassVariant.floating,
        borderRadius: radius,
        fillColorOverride: background,
        child: Material(type: MaterialType.transparency, child: content),
      );
    }
    // `Material`は`borderRadius`と`shape`を同時に指定できない。
    if (isGekiga) {
      return Material(
        color: background,
        shape: Border.all(color: GekigaColors.onPanel, width: 3),
        child: content,
      );
    }
    return Material(color: background, borderRadius: radius, child: content);
  }
}
