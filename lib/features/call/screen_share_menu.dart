import 'package:flutter/material.dart';
import '../../widgets/transitioned_overlay.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../../l10n/strings.dart';
import '../../providers/app_ui_style_provider.dart';
import '../../providers/kiwami_providers.dart';
import '../../providers/screen_share_settings_provider.dart';
import '../../router/back_stack.dart';
import '../../utils/auto_dismiss_banner.dart';
import '../../widgets/style_choice_chip.dart';
import '../../widgets/toggles/app_checkbox.dart';
import 'bgm/call_bgm_sheet.dart' show CallPanelSurface;
import 'call_controls.dart';
import 'screen_share.dart';
import 'webrtc_call_controller.dart';
import 'webrtc_group_call_controller.dart';

/// 画面共有の操作に必要なものをまとめた束（2026-11-15）。通話画面のボタン列へ、
/// 1対1・広場のコントローラーの違いを隠して渡す（`CallBgmBinding`と同じ考え方）。
class CallScreenShareBinding {
  const CallScreenShareBinding({
    required this.controller,
    required this.userId,
    required this.isSharing,
    required this.audioMissing,
    required this.start,
    required this.stop,
    required this.change,
    required this.setQuality,
    required this.setAudio,
    required this.remoteSharing,
    required this.remoteVolume,
    required this.setRemoteVolume,
  });

  /// 通話コントローラー（共有の状態が変わったら描き直す）。
  final Listenable controller;

  /// 自分のuserId（極みかの判定に使う）。
  final String userId;
  final bool Function() isSharing;

  /// 音声の共有を求めたのに、音が取れなかったか（始めた直後に確認する）。
  final bool Function() audioMissing;
  final Future<bool> Function(
    ScreenShareQuality quality,
    bool shareAudio,
    bool muteMic,
  )
  start;
  final Future<void> Function() stop;
  final Future<void> Function() change;
  final Future<void> Function(ScreenShareQuality quality) setQuality;
  final Future<void> Function(bool shareAudio) setAudio;

  /// 相手の画面共有が見えているか／その音声の音量（0〜1）／音量を変える。
  final bool Function() remoteSharing;
  final double Function() remoteVolume;
  final Future<void> Function(double volume) setRemoteVolume;
}

/// 1対1の通話の画面共有（対応しない環境はnull）。
CallScreenShareBinding? oneToOneScreenShare(
  WebrtcCallController controller,
  String userId,
) {
  if (!ScreenShareCapture.isSupported) return null;
  return CallScreenShareBinding(
    controller: controller,
    userId: userId,
    isSharing: () => controller.isScreenSharing,
    audioMissing: () => controller.screenAudioMissing,
    start: (q, audio, muteMic) => controller.startScreenShare(
      quality: q,
      shareAudio: audio,
      muteMic: muteMic,
    ),
    stop: controller.stopScreenShare,
    change: controller.changeScreenSource,
    setQuality: controller.setScreenQuality,
    setAudio: controller.setScreenAudio,
    remoteSharing: () => controller.remoteScreenShown,
    remoteVolume: () => controller.remoteScreenVolume,
    setRemoteVolume: controller.setRemoteScreenVolume,
  );
}

/// 広場の通話の画面共有（対応しない環境はnull）。
CallScreenShareBinding? groupScreenShare(WebrtcGroupCallController controller) {
  if (!ScreenShareCapture.isSupported) return null;
  return CallScreenShareBinding(
    controller: controller,
    userId: controller.currentUser.userId,
    isSharing: () => controller.isScreenSharing,
    audioMissing: () => controller.screenAudioMissing,
    start: (q, audio, muteMic) => controller.startScreenShare(
      quality: q,
      shareAudio: audio,
      muteMic: muteMic,
    ),
    stop: controller.stopScreenShare,
    change: controller.changeScreenSource,
    setQuality: controller.setScreenQuality,
    setAudio: controller.setScreenAudio,
    remoteSharing: () => controller.anyRemoteScreenShown,
    remoteVolume: () => controller.remoteScreenVolume,
    setRemoteVolume: controller.setRemoteScreenVolume,
  );
}

/// 操作バーの画面共有のボタン。押すと共有を始める／やめる。右の「^」で、画質などのメニューを開く。
class ScreenShareControl extends ConsumerWidget {
  const ScreenShareControl({
    required this.binding,
    required this.enabled,
    required this.isGekiga,
    required this.isGlass,
    super.key,
  });

  final CallScreenShareBinding binding;
  final bool enabled;
  final bool isGekiga;
  final bool isGlass;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListenableBuilder(
      listenable: binding.controller,
      builder: (context, _) {
        final sharing = binding.isSharing();
        final strings = ref.watch(appStringsProvider);
        // ボタンの右下に重ねる丸い「^」（2026-11-17）。以前は枠の余白（数px）に収めていた為、
        // 縮められて見えなくなっていた。余白からはみ出して、はっきり見える大きさにする。
        return Center(
          child: SizedBox(
            width: 56,
            height: 56,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Semantics(
                  button: true,
                  label: sharing
                      ? strings.callScreenShareStop
                      : strings.callScreenShare,
                  child: CallRoundButton(
                    icon: sharing
                        ? Icons.stop_screen_share
                        : Icons.screen_share,
                    color: sharing ? Colors.green.shade700 : Colors.grey[700]!,
                    isGekiga: isGekiga,
                    isGlass: isGlass,
                    onPressed: enabled
                        ? () => sharing
                              ? binding.stop()
                              : _start(context, ref, binding)
                        : null,
                  ),
                ),
                Positioned(
                  right: -12,
                  bottom: -10,
                  child: Opacity(
                    opacity: enabled ? 1 : 0.4,
                    child: Material(
                      color: Colors.grey[800],
                      shape: const CircleBorder(
                        side: BorderSide(color: Colors.white, width: 1.5),
                      ),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: enabled
                            ? () => showScreenShareMenu(context, binding)
                            : null,
                        child: const SizedBox(
                          width: 30,
                          height: 30,
                          child: Icon(
                            Icons.keyboard_arrow_up,
                            size: 24,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 保存した設定で共有を始める。無料の人は、高画質の設定が残っていても標準の画質で始める。
Future<void> _start(
  BuildContext context,
  WidgetRef ref,
  CallScreenShareBinding binding,
) async {
  final overlay = Overlay.maybeOf(context);
  final strings = ref.read(appStringsProvider);
  final settings = ref.read(screenShareSettingsProvider);
  final kiwami = ref.read(isKiwamiProvider(binding.userId));
  final quality = settings.quality.allowedFor(kiwami: kiwami)
      ? settings.quality
      : ScreenShareQuality.standard.copyWith(
          audioOnly: settings.quality.audioOnly,
        );
  final started = await binding.start(
    quality,
    settings.shareAudio,
    settings.muteMic,
  );
  if (started && overlay != null && binding.audioMissing()) {
    showAutoDismissBannerIn(
      overlay,
      message: strings.callScreenShareNoAudio,
      duration: const Duration(seconds: 6),
    );
  }
}

/// 画面共有のメニュー（配信を中止・変更、画質、音声）。Navigatorの無い通話画面の上に出す。
void showScreenShareMenu(BuildContext context, CallScreenShareBinding binding) {
  final overlay = Overlay.maybeOf(context);
  if (overlay == null) return;
  showTransitionedOverlay(
    overlay,
    builder: (context, close) => PointerInterceptor(
      child: BackEntry(
        scope: null,
        active: true,
        layer: true,
        onBack: close,
        child: Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: close,
              child: const ColoredBox(color: Colors.transparent),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 140, left: 8, right: 8),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: CallPanelSurface(
                    allRounded: true,
                    child: _ScreenShareMenu(binding: binding, onClose: close),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ScreenShareMenu extends ConsumerWidget {
  const _ScreenShareMenu({required this.binding, required this.onClose});

  final CallScreenShareBinding binding;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final uiStyle = ref.watch(appUiStyleProvider);
    final settings = ref.watch(screenShareSettingsProvider);
    final kiwami = ref.watch(isKiwamiProvider(binding.userId));
    final notifier = ref.read(screenShareSettingsProvider.notifier);
    final overlay = Overlay.maybeOf(context);
    final theme = Theme.of(context);

    void choose(ScreenShareQuality next) {
      if (!next.allowedFor(kiwami: kiwami)) {
        if (overlay != null) {
          showAutoDismissBannerIn(
            overlay,
            message: strings.callScreenShareKiwamiOnly,
          );
        }
        return;
      }
      notifier.setQuality(next);
      if (binding.isSharing()) binding.setQuality(next);
    }

    // 音声の切り替えは、共有中なら、すぐ送信にも反映する（入れる時は配信元を選び直す）。
    void toggleAudio(bool value) {
      notifier.setShareAudio(value);
      if (binding.isSharing()) binding.setAudio(value);
    }

    Widget checkRow(String label, bool value, void Function(bool) onChanged) =>
        InkWell(
          onTap: () => onChanged(!value),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Expanded(child: Text(label)),
                AppCheckbox(
                  value: value,
                  onChanged: (v) => onChanged(v ?? false),
                ),
              ],
            ),
          ),
        );

    Widget chip(String label, bool selected, bool locked, VoidCallback tap) =>
        StyleChoiceChip(
          uiStyle: uiStyle,
          selected: selected,
          onTap: tap,
          labelBuilder: (fg) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: TextStyle(color: fg)),
              if (locked && !kiwami) ...[
                const SizedBox(width: 4),
                Icon(Icons.lock_outline, size: 14, color: fg),
              ],
            ],
          ),
        );

    return ListenableBuilder(
      listenable: binding.controller,
      builder: (context, _) {
        final sharing = binding.isSharing();
        // ガラス・劇画の面は`Material`を作らない為、`ListTile`・`InkWell`が描けるよう、透明な
        // `Material`で包む。
        return Material(
          type: MaterialType.transparency,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (sharing) ...[
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        Icons.stop_screen_share,
                        color: Colors.red.shade700,
                      ),
                      title: Text(
                        strings.callScreenShareStop,
                        style: TextStyle(color: Colors.red.shade700),
                      ),
                      onTap: () {
                        binding.stop();
                        onClose();
                      },
                    ),
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.connected_tv),
                      title: Text(strings.callScreenShareChange),
                      onTap: () {
                        onClose();
                        binding.change();
                      },
                    ),
                    const Divider(height: 16),
                  ],
                  Text(
                    strings.callScreenShareQuality,
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    strings.callScreenShareFps,
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final fps in ScreenShareQuality.fpsOptions)
                        chip(
                          '$fps FPS',
                          settings.quality.fps == fps,
                          fps > 30,
                          () => choose(settings.quality.copyWith(fps: fps)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    strings.callScreenShareResolution,
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final h in ScreenShareQuality.heights)
                        chip(
                          '${h}p',
                          settings.quality.height == h,
                          h > 720,
                          () => choose(settings.quality.copyWith(height: h)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Androidは、端末の再生音をマイクの音声に混ぜて送る（2026-11-17、Android 10以降）。
                  // 「音声だけ共有」はAndroidでは出さない。
                  InkWell(
                    onTap: () => toggleAudio(!settings.shareAudio),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          Expanded(child: Text(strings.callScreenShareAudio)),
                          AppCheckbox(
                            value: settings.shareAudio,
                            onChanged: (v) => toggleAudio(v ?? false),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (ScreenShareCapture.isNativeAndroid && settings.shareAudio)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        strings.callScreenShareAndroidAudioNote,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  if (ScreenShareCapture.isLinuxBrowser && settings.shareAudio)
                    _LinuxMonitorPicker(
                      strings: strings,
                      selectedId: settings.linuxMonitorId,
                      onSelected: notifier.setLinuxMonitorId,
                    ),
                  if (!ScreenShareCapture.isNativeAndroid)
                    checkRow(
                      strings.callScreenShareAudioOnly,
                      settings.quality.audioOnly,
                      (v) => choose(settings.quality.copyWith(audioOnly: v)),
                    ),
                  checkRow(
                    strings.callScreenShareMuteMic,
                    settings.muteMic,
                    notifier.setMuteMic,
                  ),
                  if (binding.remoteSharing()) ...[
                    const SizedBox(height: 4),
                    Text(
                      strings.callScreenShareVolume,
                      style: theme.textTheme.bodySmall,
                    ),
                    Row(
                      children: [
                        const Icon(Icons.volume_down, size: 18),
                        Expanded(
                          child: Slider(
                            value: binding.remoteVolume(),
                            onChanged: binding.setRemoteVolume,
                          ),
                        ),
                        const Icon(Icons.volume_up, size: 18),
                      ],
                    ),
                  ],
                  if (!ScreenShareCapture.isNativeAndroid)
                    Text(
                      strings.callScreenShareAudioHint,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.6,
                        ),
                      ),
                    ),
                  const SizedBox(height: 4),
                  Text(
                    strings.callScreenShareHint,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Linuxのブラウザで、共有の音として取る「Monitor of …」入力の選択と案内（2026-11-17）。
class _LinuxMonitorPicker extends StatefulWidget {
  const _LinuxMonitorPicker({
    required this.strings,
    required this.selectedId,
    required this.onSelected,
  });

  final Strings strings;
  final String? selectedId;
  final ValueChanged<String> onSelected;

  @override
  State<_LinuxMonitorPicker> createState() => _LinuxMonitorPickerState();
}

class _LinuxMonitorPickerState extends State<_LinuxMonitorPicker> {
  late final Future<List<({String id, String label})>> _monitors =
      ScreenShareCapture.listLinuxMonitors();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = widget.strings;
    final note = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return FutureBuilder<List<({String id, String label})>>(
      future: _monitors,
      builder: (context, snapshot) {
        final monitors = snapshot.data;
        if (monitors == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (monitors.isEmpty)
                Text(strings.callScreenShareLinuxNoMonitor, style: note)
              else ...[
                if (monitors.length > 1)
                  DropdownButton<String>(
                    isExpanded: true,
                    value: ScreenShareCapture.pickMonitor(
                      monitors,
                      widget.selectedId,
                    )?.id,
                    items: [
                      for (final m in monitors)
                        DropdownMenuItem(
                          value: m.id,
                          child: Text(
                            m.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (id) {
                      if (id != null) widget.onSelected(id);
                    },
                  ),
                Text(strings.callScreenShareLinuxNote, style: note),
              ],
            ],
          ),
        );
      },
    );
  }
}
