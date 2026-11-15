import 'package:flutter/material.dart';
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
  });

  /// 通話コントローラー（共有の状態が変わったら描き直す）。
  final Listenable controller;

  /// 自分のuserId（極みかの判定に使う）。
  final String userId;
  final bool Function() isSharing;

  /// 音声の共有を求めたのに、音が取れなかったか（始めた直後に確認する）。
  final bool Function() audioMissing;
  final Future<bool> Function(ScreenShareQuality quality, bool shareAudio)
  start;
  final Future<void> Function() stop;
  final Future<void> Function() change;
  final Future<void> Function(ScreenShareQuality quality) setQuality;
  final Future<void> Function(bool shareAudio) setAudio;
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
    start: (q, audio) =>
        controller.startScreenShare(quality: q, shareAudio: audio),
    stop: controller.stopScreenShare,
    change: controller.changeScreenSource,
    setQuality: controller.setScreenQuality,
    setAudio: controller.setScreenAudio,
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
    start: (q, audio) =>
        controller.startScreenShare(quality: q, shareAudio: audio),
    stop: controller.stopScreenShare,
    change: controller.changeScreenSource,
    setQuality: controller.setScreenQuality,
    setAudio: controller.setScreenAudio,
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
        return Row(
          mainAxisSize: MainAxisSize.max,
          children: [
            const Expanded(child: SizedBox.shrink()),
            Semantics(
              button: true,
              label: sharing
                  ? strings.callScreenShareStop
                  : strings.callScreenShare,
              child: CallRoundButton(
                icon: sharing ? Icons.stop_screen_share : Icons.screen_share,
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
            // ボタンを枠の中央に保つため、左右の余白は同じ幅。「^」は右の余白に置く。
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  iconSize: 20,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 28,
                    height: 40,
                  ),
                  icon: const Icon(Icons.keyboard_arrow_up),
                  onPressed: enabled
                      ? () => showScreenShareMenu(context, binding)
                      : null,
                ),
              ),
            ),
          ],
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
      : ScreenShareQuality.standard;
  final started = await binding.start(quality, settings.shareAudio);
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
  late final OverlayEntry entry;
  void close() {
    if (entry.mounted) entry.remove();
  }

  entry = OverlayEntry(
    builder: (context) => PointerInterceptor(
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
  overlay.insert(entry);
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
                  Text(
                    strings.callScreenShareAudioHint,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
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
