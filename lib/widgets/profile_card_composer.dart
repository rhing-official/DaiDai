import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_ui_style.dart';
import '../providers/app_ui_style_provider.dart';
import 'glass/glass_surface.dart';
import 'media_preview_frame.dart';

/// [UserProfileCardDialog]（他人のプロフィールカードを見るダイアログ）専用の
/// 軽量な入力欄（2026-09-24追加）。「友達申請に添えるメッセージ欄が、
/// 通常のチャット画面のメッセージ入力欄と見た目が違いすぎてUXが悪い」
/// という指摘を受け、`chat_screen.dart`のコンポーザー（添付・ぺったん・
/// 返信バー等を持つ複雑な実装）をそのまま持ち込むのではなく、pill型の
/// `TextField`＋送信アイコンボタンという見た目の骨格だけを軽量に再現した
/// もの。添付・ぺったん等はこの用途（友達承認前の1回きりメッセージ）に
/// そもそも許可されていないため実装しない。
///
/// [enabled]がfalseの間（既にこの相手へ送信済み・返答待ちの状態）も
/// 入力欄自体は表示したままグレーアウトする（欄ごと消すとUXが分かりにくい
/// というユーザー指摘を踏まえた挙動）。
class ProfileCardComposer extends ConsumerWidget {
  const ProfileCardComposer({
    required this.controller,
    required this.enabled,
    required this.hintText,
    required this.sending,
    required this.onSend,
    this.maxLength = 100,
    this.notes = const [],
    super.key,
  });

  final TextEditingController controller;
  final bool enabled;
  final String hintText;
  final bool sending;

  /// 入力欄の枠の中、入力の下に箇条書きで出す注記（「任意」「100文字以内」等、2026-10-31）。
  final List<String> notes;

  /// nullなら送信不可（ロック中、または送信処理中）。
  final VoidCallback? onSend;
  final int maxLength;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uiStyle = ref.watch(appUiStyleProvider);
    final isGekiga = uiStyle == AppUiStyle.gekiga;
    final isGlass = uiStyle == AppUiStyle.glass;

    if (isGekiga) {
      return _GekigaComposer(
        controller: controller,
        enabled: enabled,
        hintText: hintText,
        sending: sending,
        onSend: onSend,
        maxLength: maxLength,
        notes: notes,
      );
    }

    final colorScheme = Theme.of(context).colorScheme;
    final field = TextField(
      controller: controller,
      enabled: enabled,
      minLines: 1,
      maxLines: 3,
      maxLength: maxLength,
      textInputAction: TextInputAction.done,
      onSubmitted: onSend == null ? null : (_) => onSend!(),
      decoration: InputDecoration(
        hintText: hintText,
        // 枠（角丸）は外側のコンテナが持つ。文字が枠に触れないよう内側に余白を取る。
        contentPadding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
        filled: false,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        disabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        suffixIcon: _SendButton(
          onSend: onSend,
          sending: sending,
          color: colorScheme.primary,
        ),
      ),
    );
    final inner = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        field,
        _NotesList(notes: notes, color: colorScheme.onSurfaceVariant),
      ],
    );

    if (isGlass) {
      return GlassSurface(
        variant: GlassVariant.floating,
        borderRadius: BorderRadius.circular(20),
        child: inner,
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: enabled
            ? colorScheme.surfaceContainerHighest
            : Theme.of(context).disabledColor.withValues(alpha: 0.08),
        border: Border.all(color: colorScheme.outline),
        borderRadius: BorderRadius.circular(20),
      ),
      child: inner,
    );
  }
}

/// 入力欄の枠の中に出す、箇条書きの注記。
class _NotesList extends StatelessWidget {
  const _NotesList({required this.notes, required this.color});

  final List<String> notes;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (notes.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final note in notes)
            Text(
              '・$note',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontSize: 16, color: color),
            ),
        ],
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({
    required this.onSend,
    required this.sending,
    required this.color,
  });

  final VoidCallback? onSend;
  final bool sending;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final active = onSend != null && !sending;
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        canRequestFocus: false,
        onTap: active ? onSend : null,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Icon(
            Icons.send,
            color: active ? color : color.withValues(alpha: 0.35),
          ),
        ),
      ),
    );
  }
}

/// 劇画UIでは`GekigaStraightMonochromeBox`（直線・モノクロの二重枠、
/// `link_preview_card.dart`と同じ流用パターン）で包み、白地に黒文字固定
/// にする（劇画UI全体の「モノクロボックス」意匠を崩さないため）。
class _GekigaComposer extends StatelessWidget {
  const _GekigaComposer({
    required this.controller,
    required this.enabled,
    required this.hintText,
    required this.sending,
    required this.onSend,
    required this.maxLength,
    required this.notes,
  });

  final TextEditingController controller;
  final bool enabled;
  final String hintText;
  final bool sending;
  final VoidCallback? onSend;
  final int maxLength;
  final List<String> notes;

  @override
  Widget build(BuildContext context) {
    final textColor = enabled ? Colors.black : Colors.black38;
    return GekigaStraightMonochromeBox(
      isMe: true,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: controller,
            enabled: enabled,
            minLines: 1,
            maxLines: 3,
            maxLength: maxLength,
            textInputAction: TextInputAction.done,
            onSubmitted: onSend == null ? null : (_) => onSend!(),
            style: TextStyle(color: textColor),
            cursorColor: Colors.black,
            decoration: InputDecoration(
              hintText: hintText,
              hintStyle: TextStyle(color: textColor.withValues(alpha: 0.6)),
              filled: false,
              border: InputBorder.none,
              counterStyle: TextStyle(color: textColor.withValues(alpha: 0.6)),
              suffixIcon: _SendButton(
                onSend: onSend,
                sending: sending,
                color: enabled ? Colors.black : Colors.black26,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: _NotesList(
              notes: notes,
              color: textColor.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}
