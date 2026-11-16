import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/strings.dart';
import '../../../models/soundboard_sound.dart';
import '../../../providers/group_providers.dart';
import '../../../providers/repository_providers.dart';
import '../../../providers/soundboard_providers.dart';
import '../../../repositories/soundboard_repository.dart';
import '../../../utils/auto_dismiss_banner.dart';
import '../../../utils/sound_upload.dart';
import '../bgm/call_bgm.dart';
import '../bgm/call_bgm_sheet.dart' show bgmDisplayName;
import '../call_bottom_sheet.dart';

/// 通話のサウンドボードの操作に必要なものをまとめた束（2026-11-16）。BGMと同じミキサーで
/// 効果音を重ねる為、[bgm]を使う。広場・一対とも、会話の全員が使える。
class CallSoundboardBinding {
  const CallSoundboardBinding({
    required this.bgm,
    required this.isDm,
    required this.conversationId,
    required this.userId,
  });

  final CallBgm bgm;
  final bool isDm;

  /// 一対はdmId、広場はgroupId。
  final String conversationId;
  final String userId;
}

/// 取得済みの効果音のファイル（同じ音を鳴らすたびに取り直さない）。
final Map<String, Uint8List> _bytesCache = {};

Future<void> showCallSoundboardSheet(
  BuildContext context,
  CallSoundboardBinding binding,
) {
  return showCallBottomSheet(
    context,
    builder: (context) => _CallSoundboardSheet(binding: binding),
  );
}

class _CallSoundboardSheet extends ConsumerStatefulWidget {
  const _CallSoundboardSheet({required this.binding});

  final CallSoundboardBinding binding;

  @override
  ConsumerState<_CallSoundboardSheet> createState() =>
      _CallSoundboardSheetState();
}

class _CallSoundboardSheetState extends ConsumerState<_CallSoundboardSheet> {
  bool _editing = false;
  bool _busy = false;

  CallSoundboardBinding get _binding => widget.binding;

  void _banner(String message) {
    final overlay = Overlay.maybeOf(context);
    if (overlay != null) showAutoDismissBannerIn(overlay, message: message);
  }

  Future<void> _play(SoundboardSound sound) async {
    try {
      var bytes = _bytesCache[sound.storagePath];
      if (bytes == null) {
        bytes = await ref.read(soundboardRepositoryProvider).fetchBytes(sound);
        if (bytes == null) return;
        _bytesCache[sound.storagePath] = bytes;
      }
      _binding.bgm.setEffectVolume(ref.read(soundboardVolumeProvider));
      await _binding.bgm.playEffect(sound.storagePath, bytes);
    } catch (_) {
      // 取得・デコードできない効果音は鳴らさない。
    }
  }

  Future<void> _add(Strings strings, int currentCount) async {
    if (currentCount >= kMaxSoundboardSounds) {
      _banner(strings.callSoundboardFull);
      return;
    }
    setState(() => _busy = true);
    try {
      final files = await FilePicker.pickFiles(type: FileType.audio);
      if (files.isEmpty) return;
      final file = files.first;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      await ref
          .read(soundboardRepositoryProvider)
          .addSound(
            isDm: _binding.isDm,
            conversationId: _binding.conversationId,
            userId: _binding.userId,
            name: bgmDisplayName(file.name),
            fileName: file.name,
            bytes: bytes,
          );
    } on SoundUploadTooLargeException {
      _banner(strings.callSoundboardTooLarge);
    } on SoundboardFullException {
      _banner(strings.callSoundboardFull);
    } catch (_) {
      _banner(strings.callSoundboardAddFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(SoundboardSound sound) async {
    try {
      await ref
          .read(soundboardRepositoryProvider)
          .deleteSound(
            isDm: _binding.isDm,
            conversationId: _binding.conversationId,
            sound: sound,
          );
      _bytesCache.remove(sound.storagePath);
    } catch (_) {
      // 権限が無い等。一覧はそのまま。
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final theme = Theme.of(context);
    final key = (isDm: _binding.isDm, conversationId: _binding.conversationId);
    final sounds = ref.watch(soundboardSoundsProvider(key)).value ?? const [];
    final volume = ref.watch(soundboardVolumeProvider);
    // 広場の長は、他の人が追加した効果音も削除できる。
    final isOwner =
        !_binding.isDm &&
        ref
                .watch(watchedGroupProvider(_binding.conversationId))
                .value
                ?.ownerId ==
            _binding.userId;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      strings.callSoundboardTitle,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  if (sounds.isNotEmpty)
                    TextButton(
                      onPressed: () => setState(() => _editing = !_editing),
                      child: Text(
                        _editing
                            ? strings.callSoundboardDone
                            : strings.callSoundboardEdit,
                      ),
                    ),
                  TextButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _add(strings, sounds.length),
                    icon: const Icon(Icons.add),
                    label: Text(strings.callSoundboardAdd),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Flexible(
                child: sounds.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: Text(
                            strings.callSoundboardEmpty,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      )
                    : SingleChildScrollView(
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final sound in sounds)
                              _SoundTile(
                                sound: sound,
                                editing: _editing,
                                canDelete:
                                    sound.createdBy == _binding.userId ||
                                    isOwner ||
                                    _binding.isDm,
                                onPlay: () => _play(sound),
                                onDelete: () => _delete(sound),
                              ),
                          ],
                        ),
                      ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.volume_up_outlined,
                    size: 20,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  Expanded(
                    child: Slider(
                      value: volume,
                      onChanged: (v) {
                        ref.read(soundboardVolumeProvider.notifier).set(v);
                        _binding.bgm.setEffectVolume(v);
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SoundTile extends StatelessWidget {
  const _SoundTile({
    required this.sound,
    required this.editing,
    required this.canDelete,
    required this.onPlay,
    required this.onDelete,
  });

  final SoundboardSound sound;
  final bool editing;
  final bool canDelete;
  final VoidCallback onPlay;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final showDelete = editing && canDelete;
    return OutlinedButton(
      onPressed: showDelete ? onDelete : (editing ? null : onPlay),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 140),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              showDelete ? Icons.close : Icons.play_arrow,
              size: 18,
              color: showDelete ? Colors.red.shade700 : null,
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                sound.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
