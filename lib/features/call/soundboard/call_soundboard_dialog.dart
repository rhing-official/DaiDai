import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../../../l10n/strings.dart';
import '../../../models/soundboard_sound.dart';
import '../../../providers/kiwami_providers.dart';
import '../../../providers/repository_providers.dart';
import '../../../repositories/soundboard_repository.dart';
import '../../../router/back_stack.dart';
import '../../../utils/auto_dismiss_banner.dart';
import '../../../utils/sound_upload.dart';
import '../../../widgets/transitioned_overlay.dart';
import '../bgm/call_bgm_sheet.dart' show CallPanelSurface, bgmDisplayName;
import 'call_soundboard_popup.dart' show CallSoundboardBinding;

/// サウンドの追加（[editing]がnull）・名前と音量の変更（[editing]を渡す）の画面（2026-11-17）。
/// Navigatorの無い通話画面（PC・Webの`CallOverlay`）でも出せるよう、`Overlay`へ直接出す。
void showSoundboardSoundDialog(
  BuildContext context, {
  required CallSoundboardBinding binding,
  SoundboardSound? editing,
}) {
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
              child: ColoredBox(color: Colors.black.withValues(alpha: 0.5)),
            ),
            Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: CallPanelSurface(
                    allRounded: true,
                    child: _SoundDialogBody(
                      binding: binding,
                      editing: editing,
                      close: close,
                    ),
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

class _SoundDialogBody extends ConsumerStatefulWidget {
  const _SoundDialogBody({
    required this.binding,
    required this.editing,
    required this.close,
  });

  final CallSoundboardBinding binding;
  final SoundboardSound? editing;
  final VoidCallback close;

  @override
  ConsumerState<_SoundDialogBody> createState() => _SoundDialogBodyState();
}

class _SoundDialogBodyState extends ConsumerState<_SoundDialogBody> {
  late final TextEditingController _name = TextEditingController(
    text: widget.editing?.name ?? '',
  );
  late double _volume = widget.editing?.volume ?? 1.0;
  String? _fileName;
  Uint8List? _bytes;
  bool _busy = false;

  bool get _isEdit => widget.editing != null;

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      !_busy && _name.text.trim().isNotEmpty && (_isEdit || _bytes != null);

  void _banner(String message) {
    final overlay = Overlay.maybeOf(context);
    if (overlay != null) showAutoDismissBannerIn(overlay, message: message);
  }

  Future<void> _browse(Strings strings) async {
    try {
      final files = await FilePicker.pickFiles(type: FileType.audio);
      if (files.isEmpty) return;
      final file = files.first;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      try {
        validateSoundUpload(bytes, file.name);
        if (bytes.lengthInBytes > kMaxSoundboardSoundBytes) {
          throw const SoundUploadTooLargeException();
        }
      } on SoundUploadTooLargeException {
        _banner(strings.callSoundboardTooLarge);
        return;
      } on SoundUploadUnsupportedFormatException {
        _banner(strings.callSoundboardAddFailed);
        return;
      }
      setState(() {
        _fileName = file.name;
        _bytes = bytes;
        // 名前が空のままなら、ファイル名（拡張子なし）を入れる。
        if (_name.text.trim().isEmpty) _name.text = bgmDisplayName(file.name);
      });
    } catch (_) {
      _banner(strings.callSoundboardAddFailed);
    }
  }

  Future<void> _submit(Strings strings) async {
    if (!_canSubmit) return;
    setState(() => _busy = true);
    final repo = ref.read(soundboardRepositoryProvider);
    final b = widget.binding;
    try {
      final editing = widget.editing;
      if (editing != null) {
        await repo.updateSound(
          isDm: b.isDm,
          conversationId: b.conversationId,
          sound: editing,
          name: _name.text,
          volume: _volume,
        );
      } else {
        // 上限は1人あたり（無料5個・極み10個、2026-11-17）。
        final limit = soundboardLimitFor(
          kiwami: ref.read(isKiwamiProvider(b.userId)),
        );
        if (await repo.countMySounds(b.userId) >= limit) {
          _banner(strings.callSoundboardFull);
          return;
        }
        await repo.addSound(
          isDm: b.isDm,
          conversationId: b.conversationId,
          userId: b.userId,
          name: _name.text.trim(),
          fileName: _fileName!,
          bytes: _bytes!,
          limit: limit,
          volume: _volume,
        );
      }
      widget.close();
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

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = theme.textTheme.labelLarge?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _isEdit
                      ? strings.callSoundboardEditTitle
                      : strings.callSoundboardUploadTitle,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: widget.close,
              ),
            ],
          ),
          if (!_isEdit) ...[
            const SizedBox(height: 12),
            Text(strings.callSoundboardFile, style: muted),
            const SizedBox(height: 6),
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: _busy ? null : () => _browse(strings),
              child: Container(
                padding: const EdgeInsets.only(left: 12, right: 4),
                height: 44,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: scheme.outlineVariant),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.upload_outlined,
                      size: 20,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _fileName ?? strings.callSoundboardChooseFile,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _fileName == null
                              ? scheme.onSurfaceVariant
                              : scheme.onSurface,
                        ),
                      ),
                    ),
                    OutlinedButton(
                      onPressed: _busy ? null : () => _browse(strings),
                      child: Text(strings.callSoundboardBrowse),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Text(strings.callSoundboardName, style: muted),
          const SizedBox(height: 6),
          TextField(
            controller: _name,
            maxLength: kMaxSoundboardNameLength,
            decoration: InputDecoration(
              hintText: strings.callSoundboardNameHint,
              isDense: true,
              counterText: '',
            ),
            onSubmitted: (_) => _submit(strings),
          ),
          const SizedBox(height: 16),
          Text(strings.callSoundboardVolume, style: muted),
          Slider(value: _volume, onChanged: (v) => setState(() => _volume = v)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: widget.close,
                  child: Text(strings.callSoundboardCancel),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _canSubmit ? () => _submit(strings) : null,
                  child: Text(
                    _isEdit
                        ? strings.callSoundboardSave
                        : strings.callSoundboardUpload,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
