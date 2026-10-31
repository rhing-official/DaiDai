import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../l10n/strings.dart';

/// 通話中の音声の出力先（スピーカー・受話口・Bluetooth・有線ヘッドセットなど）を
/// 選ぶシート（2026-10-31追加）。スピーカーのボタンから開く。端末が出力先を
/// 2つ以上返さない（選べるものが無い）場合は、従来どおりスピーカーのオン/オフ
/// ([onFallbackToggle])に切り替える。
Future<void> showCallAudioOutputPicker(
  BuildContext context,
  WidgetRef ref, {
  required VoidCallback onFallbackToggle,
}) async {
  List<MediaDeviceInfo> outputs;
  try {
    outputs = await Helper.audiooutputs;
  } catch (_) {
    outputs = const [];
  }
  if (!context.mounted) return;
  if (outputs.length < 2) {
    onFallbackToggle();
    return;
  }
  final title = ref.read(appStringsProvider).callAudioOutputTitle;
  await showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              title,
              style: Theme.of(sheetContext).textTheme.titleMedium,
            ),
          ),
          for (final device in outputs)
            ListTile(
              leading: const Icon(Icons.volume_up),
              title: Text(
                device.label.isEmpty ? device.deviceId : device.label,
              ),
              onTap: () async {
                Navigator.of(sheetContext).pop();
                try {
                  await Helper.selectAudioOutput(device.deviceId);
                } catch (_) {
                  // 切り替えられない出力先。現状維持。
                }
              },
            ),
        ],
      ),
    ),
  );
}
