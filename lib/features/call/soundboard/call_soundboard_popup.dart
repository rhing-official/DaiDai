import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../../../l10n/strings.dart';
import '../../../models/soundboard_sound.dart';
import '../../../providers/group_providers.dart';
import '../../../providers/repository_providers.dart';
import '../../../providers/soundboard_providers.dart';
import '../../../router/back_stack.dart';
import '../../../widgets/transitioned_overlay.dart';
import '../bgm/call_bgm.dart';
import '../bgm/call_bgm_sheet.dart' show CallPanelSurface;
import 'call_soundboard_dialog.dart';

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

/// サウンドボードのポップアップを、ボタン（[anchorRect]、画面座標）の真上に出す（2026-11-17）。
/// 暗幕は出さない。外側のクリック・Esc・戻るで閉じる。Navigatorの無い通話画面
/// （PC・Webの`CallOverlay`）でも出せるよう、`Overlay`へ直接出す。
void showCallSoundboardPopup(
  BuildContext context,
  CallSoundboardBinding binding, {
  required Rect anchorRect,
}) {
  final overlay = Overlay.maybeOf(context);
  if (overlay == null) return;
  final overlayBox = overlay.context.findRenderObject() as RenderBox?;
  final screen = overlayBox?.size ?? MediaQuery.sizeOf(context);
  const pad = 8.0;
  final width = math.min(560.0, screen.width - pad * 2);
  final left = (anchorRect.center.dx - width / 2)
      .clamp(pad, math.max(pad, screen.width - width - pad))
      .toDouble();
  // ボタンの上端から少し離して、その上に出す（高さの上限も、そこから上の空きに収める）。
  final bottom = screen.height - anchorRect.top + 8;
  final maxHeight = math.max(160.0, anchorRect.top - 8 - pad);
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
            // 見えない障壁（暗幕なし）。外側のクリックで閉じる。
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: close,
              child: const SizedBox.expand(),
            ),
            Positioned(
              left: left,
              bottom: bottom,
              width: width,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxHeight),
                child: CallPanelSurface(
                  allRounded: true,
                  child: _SoundboardPopup(binding: binding),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _SoundboardPopup extends ConsumerStatefulWidget {
  const _SoundboardPopup({required this.binding});

  final CallSoundboardBinding binding;

  @override
  ConsumerState<_SoundboardPopup> createState() => _SoundboardPopupState();
}

class _SoundboardPopupState extends ConsumerState<_SoundboardPopup> {
  final _search = TextEditingController();

  CallSoundboardBinding get _binding => widget.binding;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
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
      await _binding.bgm.playEffect(
        sound.storagePath,
        bytes,
        gain: sound.volume,
      );
    } catch (_) {
      // 取得・デコードできない効果音は鳴らさない。
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
    final scheme = theme.colorScheme;
    final key = (isDm: _binding.isDm, conversationId: _binding.conversationId);
    final all = ref.watch(soundboardSoundsProvider(key)).value ?? const [];
    final sounds = filterSoundboardSounds(all, _search.text);
    final volume = ref.watch(soundboardVolumeProvider);
    // 広場の長は、他の人が追加したサウンドも変更・削除できる。
    final isOwner =
        !_binding.isDm &&
        ref
                .watch(watchedGroupProvider(_binding.conversationId))
                .value
                ?.ownerId ==
            _binding.userId;
    bool canManage(SoundboardSound s) =>
        _binding.isDm || s.createdBy == _binding.userId || isOwner;

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _search,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: strings.callSoundboardSearchHint,
                    isDense: true,
                    prefixIcon: const Icon(Icons.search, size: 20),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          Row(
            children: [
              Icon(
                volume <= 0 ? Icons.volume_off : Icons.volume_up,
                size: 20,
                color: scheme.onSurfaceVariant,
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
          Flexible(
            child: SingleChildScrollView(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  const gap = 8.0;
                  final tileWidth = (constraints.maxWidth - gap * 2) / 3;
                  return Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      for (final sound in sounds)
                        SizedBox(
                          width: tileWidth,
                          child: _SoundTile(
                            sound: sound,
                            canManage: canManage(sound),
                            onPlay: () => _play(sound),
                            onEdit: () => showSoundboardSoundDialog(
                              context,
                              binding: _binding,
                              editing: sound,
                            ),
                            onDelete: () => _delete(sound),
                          ),
                        ),
                      SizedBox(
                        width: tileWidth,
                        child: _AddTile(
                          label: strings.callSoundboardAdd,
                          onTap: () => showSoundboardSoundDialog(
                            context,
                            binding: _binding,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          if (all.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                strings.callSoundboardEmpty,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            )
          else if (sounds.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                strings.callSoundboardNoResults,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SoundTile extends StatefulWidget {
  const _SoundTile({
    required this.sound,
    required this.canManage,
    required this.onPlay,
    required this.onEdit,
    required this.onDelete,
  });

  final SoundboardSound sound;
  final bool canManage;
  final VoidCallback onPlay;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  State<_SoundTile> createState() => _SoundTileState();
}

class _SoundTileState extends State<_SoundTile>
    with SingleTickerProviderStateMixin {
  /// クリックした時の反応（ぽんと縮んで戻り、アクセントの色が広がって消える、2026-11-17）。
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 450),
  );

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  void _tap() {
    _pulse.forward(from: 0);
    widget.onPlay();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sound = widget.sound;
    final canManage = widget.canManage;
    final onEdit = widget.onEdit;
    final onDelete = widget.onDelete;
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) {
        final t = _pulse.value;
        // 前半で0.94まで縮み、後半で戻る。
        final scale = 1 - 0.06 * math.sin(math.pi * t);
        return Transform.scale(
          scale: scale,
          child: Material(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                child!,
                // 左から色が走り、全体が染まってから消える。
                if (_pulse.isAnimating)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: Curves.easeOut.transform(
                          (t * 1.6).clamp(0.0, 1.0),
                        ),
                        child: ColoredBox(
                          color: scheme.primary.withValues(
                            alpha: 0.45 * (1 - t),
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
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: _tap,
        child: SizedBox(
          height: 40,
          child: Row(
            children: [
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  sound.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: scheme.onSurface),
                ),
              ),
              if (canManage) ...[
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 32,
                    height: 32,
                  ),
                  icon: Icon(
                    Icons.edit_outlined,
                    size: 16,
                    color: scheme.onSurface,
                  ),
                  onPressed: onEdit,
                ),
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 32,
                    height: 32,
                  ),
                  icon: Icon(Icons.close, size: 16, color: Colors.red.shade700),
                  onPressed: onDelete,
                ),
              ] else
                const SizedBox(width: 6),
            ],
          ),
        ),
      ),
    );
  }
}

/// 「＋ サウンドを追加」（点線の枠）。
class _AddTile extends StatelessWidget {
  const _AddTile({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CustomPaint(
      foregroundPainter: _DashedBorderPainter(color: scheme.outline),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: SizedBox(
          height: 40,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add, size: 18, color: scheme.onSurface),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: scheme.onSurface),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(8)),
      );
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(metric.extractPath(distance, distance + 4), paint);
        distance += 7;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) => old.color != color;
}
